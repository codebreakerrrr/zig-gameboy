const std = @import("std");
const lcd_w = @import("emulator.zig").LCD_WIDTH;
const lcd_h = @import("emulator.zig").LCD_HEIGHT;

pub const Ppu = struct {
    // very minimal PPU placeholder
    scanline: u8 = 0,

    pub fn reset(self: *Ppu) void {
        self.* = .{};
    }

    pub fn step(self: *Ppu, cycles: u32) void {
        _ = cycles;
        // do nothing for now
        _ = self;
    }

    pub fn renderTestPattern(fb: []u32, t: f64) void {
        // Fill fb with a gradient and pulse
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
