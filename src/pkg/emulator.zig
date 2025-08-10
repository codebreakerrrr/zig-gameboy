const std = @import("std");
const Cartridge = @import("cartridge.zig").Cartridge;
const Cpu = @import("cpu.zig").Cpu;
const MMU = @import("mmu.zig").MMU;
const Ppu = @import("ppu.zig").Ppu;

pub const LCD_WIDTH: usize = 160;
pub const LCD_HEIGHT: usize = 144;

pub const Emulator = struct {
    cart: Cartridge,
    mmu: MMU,
    cpu: Cpu,
    ppu: Ppu,
    // Simple RGBA8 framebuffer
    fb: [LCD_WIDTH * LCD_HEIGHT]u32,
    t_accum: f64,

    pub fn init(allocator: std.mem.Allocator, cart: Cartridge) !Emulator {
        _ = allocator; // unused for now
        var emu = Emulator{
            .cart = cart,
            .mmu = MMU.init(cart),
            .cpu = .{},
            .ppu = .{},
            .fb = undefined,
            .t_accum = 0,
        };
        emu.cpu.reset();
        emu.ppu.reset();
        // Fill with a test pattern
        for (0..LCD_HEIGHT) |y| {
            for (0..LCD_WIDTH) |x| {
                const checker = ((x / 8 + y / 8) & 1) == 0;
                const r: u8 = if (checker) 0xE0 else 0x30;
                const g: u8 = if (checker) 0xF0 else 0x30;
                const b: u8 = if (checker) 0xD0 else 0x30;
                emu.fb[y * LCD_WIDTH + x] = packRGBA(r, g, b, 0xFF);
            }
        }
        return emu;
    }

    pub fn deinit(self: *Emulator, allocator: std.mem.Allocator) void {
        _ = allocator; // nothing to free yet
        // Note: cart memory owned by Emulator? Here we borrowed; the caller will free it.
        _ = self;
    }

    pub fn step(self: *Emulator, dt_sec: f64) !void {
        // Convert dt to CPU cycles. DMG runs at ~4_194_304 Hz.
        const cycles_to_run: u32 = @intFromFloat(dt_sec * 4_194_304.0);
        var spent: u32 = 0;
        while (spent < cycles_to_run) {
            const c = self.cpu.step(&self.mmu);
            self.ppu.step(c);
            spent += c;
        }
        self.t_accum += dt_sec;
        // Render placeholder pattern into fb for now
        Ppu.renderTestPattern(&self.fb, self.t_accum);
    }

    pub fn framebuffer(self: *Emulator) []const u32 {
        return &self.fb;
    }
};

fn packRGBA(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | @as(u32, a);
}

fn satAdd(a: u8, b: u8) u8 {
    const sum: u16 = @as(u16, a) + @as(u16, b);
    return if (sum > 255) 255 else @intCast(sum);
}
