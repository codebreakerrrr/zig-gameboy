const std = @import("std");
const Cartridge = @import("cartridge.zig").Cartridge;
const Joypad = @import("joypad.zig").Joypad;
const Timer = @import("timer.zig").Timer;
const interrupt = @import("interrupt.zig");

pub const Mmu = struct {
    cart: *Cartridge,

    vram: [0x2000]u8 = [_]u8{0} ** 0x2000,
    wram: [0x2000]u8 = [_]u8{0} ** 0x2000,
    oam:  [0x00A0]u8 = [_]u8{0} ** 0x00A0,
    hram: [0x007F]u8 = [_]u8{0} ** 0x007F,

    io: [0x80]u8 = [_]u8{0} ** 0x80,
    ie: u8 = 0,

    joypad: Joypad = .{},
    timer: Timer = .{},

    pub fn init(cart: *Cartridge) Mmu {
        var m = Mmu{ .cart = cart };
        m.io[0x00] = 0xCF;
        m.io[0x47] = 0xFC;
        m.io[0x40] = 0x91;
        m.io[0x41] = 0x85;
        return m;
    }

    pub inline fn requestInterrupt(self: *Mmu, bit_index: u8) void {
        const b = interrupt.bit(bit_index);
        self.io[0x0F] |= b;
    }

    pub fn read8(self: *Mmu, addr: u16) u8 {
        const a = addr;
        return switch (a) {
            0x0000...0x7FFF => self.cart.romRead(a),
            0x8000...0x9FFF => self.vram[a - 0x8000],
            0xA000...0xBFFF => self.cart.extRamRead(a),
            0xC000...0xDFFF => self.wram[a - 0xC000],
            0xE000...0xFDFF => self.wram[a - 0xE000],
            0xFE00...0xFE9F => self.oam[a - 0xFE00],
            0xFEA0...0xFEFF => 0xFF,
            0xFF00 => self.joypad.readP1(),
            0xFF04...0xFF07 => self.timer.read(a),
            0xFF0F => self.io[0x0F],
            0xFF10...0xFF7F => self.io[a - 0xFF00],
            0xFF80...0xFFFE => self.hram[a - 0xFF80],
            0xFFFF => self.ie,
            else => 0xFF,
        };
    }

    pub fn write8(self: *Mmu, addr: u16, value: u8) void {
        const a = addr;
        switch (a) {
            0x0000...0x7FFF => self.cart.write(a, value),
            0x8000...0x9FFF => self.vram[a - 0x8000] = value,
            0xA000...0xBFFF => self.cart.extRamWrite(a, value),
            0xC000...0xDFFF => self.wram[a - 0xC000] = value,
            0xE000...0xFDFF => self.wram[a - 0xE000] = value,
            0xFE00...0xFE9F => self.oam[a - 0xFE00] = value,
            0xFEA0...0xFEFF => {},
            0xFF00 => self.joypad.writeP1(value),
            0xFF04...0xFF07 => self.timer.write(a, value),
            0xFF0F => self.io[0x0F] = value,
            0xFF10...0xFF7F => self.io[a - 0xFF00] = value,
            0xFF80...0xFFFE => self.hram[a - 0xFF80] = value,
            0xFFFF => self.ie = value,
            else => {},
        }
    }

    pub inline fn read16(self: *Mmu, addr: u16) u16 {
        const lo = self.read8(addr);
        const hi = self.read8(addr + 1);
        return (@as(u16, hi) << 8) | lo;
    }
    pub inline fn write16(self: *Mmu, addr: u16, value: u16) void {
        self.write8(addr, @intCast(value & 0xFF));
        self.write8(addr + 1, @intCast(value >> 8));
    }
};
