const std = @import("std");
const Cartridge = @import("cartridge.zig").Cartridge;
const Cpu = @import("cpu.zig").Cpu;
const Mmu = @import("mmu.zig").Mmu;
const Ppu = @import("ppu.zig").Ppu;
const Apu = @import("apu.zig").Apu;
const interrupt = @import("interrupt.zig");

pub const LCD_WIDTH: usize = 160;
pub const LCD_HEIGHT: usize = 144;

pub const Emulator = struct {
    cart: Cartridge,
    mmu: Mmu,
    cpu: Cpu,
    ppu: Ppu,
    apu: Apu,
    // Simple RGBA8 framebuffer
    fb: [LCD_WIDTH * LCD_HEIGHT]u32,
    t_accum: f64,

    pub fn init(allocator: std.mem.Allocator, cart: Cartridge) !Emulator {
        _ = allocator; // unused for now
        var emu = Emulator{
            .cart = cart,
            .mmu = undefined,
            .cpu = undefined,
            .ppu = undefined,
            .apu = undefined,
            .fb = undefined,
            .t_accum = 0,
        };
        emu.mmu = Mmu.init(&emu.cart);
        emu.cpu = Cpu.init(&emu.mmu);
        emu.ppu = Ppu.init(&emu.mmu, &emu.fb);
        emu.ppu.reset();
    emu.apu = Apu.init();
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
        _ = allocator;
        self.cart.deinit();
    }

    pub fn step(self: *Emulator, dt_sec: f64) !void {
        // Convert dt to CPU cycles. DMG runs at ~4_194_304 Hz.
        const cycles_to_run: u32 = @intFromFloat(dt_sec * 4_194_304.0);
        var spent: u32 = 0;
        while (spent < cycles_to_run) {
            const c = self.cpu.step();
            if (self.mmu.timer.step(c)) self.mmu.requestInterrupt(interrupt.IF_TIMER);
            self.ppu.step(c);
            self.apu.step(c);
            spent += c;
        }
        self.t_accum += dt_sec;
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
