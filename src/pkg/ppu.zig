const std = @import("std");
const lcd_w = @import("emulator.zig").LCD_WIDTH;
const lcd_h = @import("emulator.zig").LCD_HEIGHT;
const Mmu = @import("mmu.zig").Mmu;
const interrupt = @import("interrupt.zig");

pub const Ppu = struct {
    mmu: *Mmu,
    framebuffer: []u32,

    dot_counter: u32 = 0,
    ly: u8 = 0,

    pub fn init(mmu: *Mmu, framebuffer: []u32) Ppu {
        return .{ .mmu = mmu, .framebuffer = framebuffer };
    }

    pub fn reset(self: *Ppu) void {
        self.dot_counter = 0;
        self.ly = 0;
        self.mmu.io[0x44] = 0; // LY
        self.mmu.io[0x41] = (self.mmu.io[0x41] & 0xF8) | 0; // mode 0
    }

    pub fn step(self: *Ppu, cycles: u32) void {
        if ((self.mmu.io[0x40] & 0x80) == 0) {
            self.dot_counter = 0;
            self.ly = 0;
            self.mmu.io[0x44] = 0;
            self.setMode(0);
            return;
        }

        self.dot_counter += cycles;
        while (self.dot_counter >= 456) {
            self.dot_counter -= 456;
            if (self.ly < 144) {
                self.renderLine(self.ly);
            }
            self.ly +%= 1;
            self.mmu.io[0x44] = self.ly;
            self.updateStatCoincidence();

            if (self.ly == 144) {
                self.setMode(1);
                self.mmu.requestInterrupt(interrupt.IF_VBLANK);
                if ((self.mmu.io[0x41] & 0x10) != 0) self.mmu.requestInterrupt(interrupt.IF_STAT);
            } else if (self.ly > 153) {
                self.ly = 0;
                self.mmu.io[0x44] = 0;
                self.setMode(2);
                if ((self.mmu.io[0x41] & 0x20) != 0) self.mmu.requestInterrupt(interrupt.IF_STAT);
            } else if (self.ly < 144) {
                self.setModeByDot();
            } else {
                self.setMode(1);
            }
        }
        if (self.ly < 144) self.setModeByDot();
    }

    fn setModeByDot(self: *Ppu) void {
        const dots = self.dot_counter;
        const prev_mode = self.mmu.io[0x41] & 0x03;
        const mode: u8 = if (dots < 80) 2 else if (dots < (80 + 172)) 3 else 0;
        if (mode != prev_mode) {
            self.setMode(mode);
            const stat = self.mmu.io[0x41];
            if (mode == 2 and (stat & 0x20) != 0) self.mmu.requestInterrupt(interrupt.IF_STAT);
            if (mode == 0 and (stat & 0x08) != 0) self.mmu.requestInterrupt(interrupt.IF_STAT);
        }
    }

    fn setMode(self: *Ppu, mode: u8) void {
        self.mmu.io[0x41] = (self.mmu.io[0x41] & 0xFC) | (mode & 0x03);
    }

    fn updateStatCoincidence(self: *Ppu) void {
        const lyc = self.mmu.io[0x45];
        const equal = (self.ly == lyc);
        if (equal) {
            self.mmu.io[0x41] |= 0x04;
            if ((self.mmu.io[0x41] & 0x40) != 0) self.mmu.requestInterrupt(interrupt.IF_STAT);
        } else {
            self.mmu.io[0x41] &= ~@as(u8, 0x04);
        }
    }

    fn renderLine(self: *Ppu, y: u8) void {
        const lcdc = self.mmu.io[0x40];
        // If LCD disabled, white line
        if ((lcdc & 0x80) == 0 or (lcdc & 0x01) == 0) {
            var x: usize = 0;
            const row = @as(usize, y) * lcd_w;
            while (x < lcd_w) : (x += 1) self.framebuffer[row + x] = 0xFFFFFFFF;
            return;
        }
        const scy = self.mmu.io[0x42];
        const scx = self.mmu.io[0x43];
        const bg_map_base: u16 = if ((lcdc & 0x08) != 0) 0x9C00 else 0x9800;
        const tile_data_8000: bool = (lcdc & 0x10) != 0;

        const v_y: u8 = scy +% y;
        const tile_row: u16 = (@as(u16, v_y) / 8) * 32;
        const fine_y: u8 = v_y & 7;
        const bgp = self.mmu.io[0x47];

        var x: usize = 0;
        const fb_row = @as(usize, y) * lcd_w;
        while (x < lcd_w) : (x += 1) {
            const v_x: u8 = scx +% @as(u8, @intCast(x));
            const tile_col: u16 = (@as(u16, v_x) / 8);
            const tile_index_addr: u16 = bg_map_base + tile_row + tile_col;
            const tile_index: i16 = @intCast(self.mmu.vram[tile_index_addr - 0x8000]);
            var tile_addr: u16 = 0;
            if (tile_data_8000) {
                tile_addr = 0x8000 + @as(u16, @intCast(tile_index)) * 16;
            } else {
                const sidx: i16 = @as(i8, @intCast(tile_index));
                tile_addr = 0x9000 + @as(u16, @intCast(sidx)) * 16;
            }
            const b0 = self.mmu.vram[(tile_addr + fine_y * 2 - 0x8000)];
            const b1 = self.mmu.vram[(tile_addr + fine_y * 2 + 1 - 0x8000)];
            const bit: u3 = @intCast(7 - (v_x & 7));
            const lo = (b0 >> bit) & 1;
            const hi = (b1 >> bit) & 1;
            const color_id: u8 = (hi << 1) | lo;
            const shade = mapPaletteDMG(bgp, color_id);
            self.framebuffer[fb_row + x] = shade;
        }

        // Window layer
        if ((lcdc & 0x20) != 0) {
            const wy = self.mmu.io[0x4A];
            const wx = self.mmu.io[0x4B];
            if (y >= wy and wx <= 166) {
                const win_map_base: u16 = if ((lcdc & 0x40) != 0) 0x9C00 else 0x9800;
                const win_y: u8 = y - wy;
                const win_tile_row: u16 = (@as(u16, win_y) / 8) * 32;
                const win_fine_y: u8 = win_y & 7;
                var sx: usize = if (wx >= 7) (wx - 7) else 0;
                while (sx < lcd_w) : (sx += 1) {
                    const win_x = @as(u8, @intCast(sx - (if (wx > 7) (wx - 7) else 0)));
                    const tile_col: u16 = (@as(u16, win_x) / 8);
                    const tile_index_addr: u16 = win_map_base + win_tile_row + tile_col;
                    const tile_index: i16 = @intCast(self.mmu.vram[tile_index_addr - 0x8000]);
                    var tile_addr: u16 = 0;
                    if (tile_data_8000) {
                        tile_addr = 0x8000 + @as(u16, @intCast(tile_index)) * 16;
                    } else {
                        const sidx: i16 = @as(i8, @intCast(tile_index));
                        tile_addr = 0x9000 + @as(u16, @intCast(sidx)) * 16;
                    }
                    const b0 = self.mmu.vram[(tile_addr + win_fine_y * 2 - 0x8000)];
                    const b1 = self.mmu.vram[(tile_addr + win_fine_y * 2 + 1 - 0x8000)];
                    const bit: u3 = @intCast(7 - (win_x & 7));
                    const lo = (b0 >> bit) & 1;
                    const hi = (b1 >> bit) & 1;
                    const color_id: u8 = (hi << 1) | lo;
                    const shade = mapPaletteDMG(bgp, color_id);
                    self.framebuffer[fb_row + sx] = shade;
                }
            }
        }

        // Sprites (OAM)
        if ((lcdc & 0x02) != 0) {
            const obj_size_8x16 = (lcdc & 0x04) != 0;
            const obp0 = self.mmu.io[0x48];
            const obp1 = self.mmu.io[0x49];
            // Collect up to 10 sprites intersecting this scanline
            var found: usize = 0;
            var indices: [10]u8 = undefined;
            var i: usize = 0;
            while (i < 40 and found < 10) : (i += 1) {
                const base = i * 4;
                const sy = self.mmu.oam[base + 0];
                const sx = self.mmu.oam[base + 1];
                const tile = self.mmu.oam[base + 2];
                const flags = self.mmu.oam[base + 3];
                const height: u8 = if (obj_size_8x16) 16 else 8;
                const top: i16 = @as(i16, sy) - 16;
                if (@as(i16, y) >= top and @as(i16, y) < top + @as(i16, height)) {
                    indices[found] = @intCast(i);
                    found += 1;
                }
                _ = sx; _ = tile; _ = flags; // kept for later
            }
            // Render in OAM order (ties resolved by X later)
            var s: usize = 0;
            while (s < found) : (s += 1) {
                const oi: usize = indices[s];
                const base = oi * 4;
                const sy = self.mmu.oam[base + 0];
                const sx = self.mmu.oam[base + 1];
                var tile = self.mmu.oam[base + 2];
                const flags = self.mmu.oam[base + 3];
                const pal = if ((flags & 0x10) != 0) obp1 else obp0;
                const flip_x = (flags & 0x20) != 0;
                const flip_y = (flags & 0x40) != 0;
                const bg_prio = (flags & 0x80) != 0;
                const height: u8 = if (obj_size_8x16) 16 else 8;
                const top_i: i16 = @as(i16, sy) - 16;
                var line: i16 = @as(i16, y) - top_i;
                if (flip_y) line = (@as(i16, height) - 1) - line;
                if (obj_size_8x16) tile &= 0xFE; // 8x16 uses two tiles
                const line_low: u16 = @intCast(line & 0x07);
                const bank_off: u16 = if (line >= 8) 16 else 0;
                const tile_addr: u16 = 0x8000 + @as(u16, tile) * 16 + line_low * 2 + bank_off;
                const b0 = self.mmu.vram[(tile_addr - 0x8000)];
                const b1 = self.mmu.vram[(tile_addr - 0x8000 + 1)];
                var px: u8 = 0;
                while (px < 8) : (px += 1) {
                    const screen_x_i: i16 = @as(i16, sx) - 8 + @as(i16, px);
                    if (screen_x_i < 0 or screen_x_i >= lcd_w) continue;
                    const dibit_index: u3 = @intCast(if (flip_x) px else 7 - px);
                    const lo = (b0 >> dibit_index) & 1;
                    const hi = (b1 >> dibit_index) & 1;
                    const color_id: u8 = (hi << 1) | lo;
                    if (color_id == 0) continue; // transparent
                    const idx: usize = fb_row + @as(usize, @intCast(screen_x_i));
                    if (bg_prio) {
                        // If BG pixel not white (color_id != 0), skip
                        // We estimate by sampling bgp mapping; treat 0 as behind
                        // Here: if framebuffer already not white, skip
                        if (self.framebuffer[idx] != 0xFFFFFFFF) continue;
                    }
                    self.framebuffer[idx] = mapPaletteDMG(pal, color_id);
                }
            }
        }
    }

    inline fn mapPaletteDMG(pal: u8, color_id: u8) u32 {
        const shift: u3 = @intCast((color_id & 0x03) * 2);
        const idx2 = (pal >> shift) & 0x03;
        const c: u8 = switch (idx2) { 0 => 0xE0, 1 => 0xA8, 2 => 0x60, 3 => 0x20, else => 0xFF };
        return (@as(u32, c) << 24) | (@as(u32, c) << 16) | (@as(u32, c) << 8) | 0xFF;
    }

    pub fn renderTestPattern(fb: []u32, t: f64) void {
        const pulse: f64 = (std.math.sin(t * 2.0 * std.math.pi) * 0.5 + 0.5);
        const shift: u8 = @intFromFloat(pulse * 120.0);
        var y: usize = 0;
        while (y < lcd_h) : (y += 1) {
            var x: usize = 0;
            while (x < lcd_w) : (x += 1) {
                const base: u8 = @intCast((x * 255) / lcd_w);
                const r: u8 = base;
                const g: u8 = @intCast((y * 255) / lcd_h);
                const b: u8 = shift;
                fb[y * lcd_w + x] = (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | 0xFF;
            }
        }
    }
};
