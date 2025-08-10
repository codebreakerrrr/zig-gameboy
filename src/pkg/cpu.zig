const std = @import("std");
const MMU = @import("mmu.zig").MMU;

pub const Cpu = struct {
    // 8-bit registers
    a: u8 = 0,
    f: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    h: u8 = 0,
    l: u8 = 0,

    sp: u16 = 0,
    pc: u16 = 0,

    ime: bool = false, // interrupt master enable

    pub fn reset(self: *Cpu) void {
        // DMG boot typically sets CPU state; for now, use common post-boot values
        self.* = .{};
        self.a = 0x01; // DMG: A=0x01
        self.f = 0xB0; // Z, -, H, C flags set
        self.b = 0x00; self.c = 0x13;
        self.d = 0x00; self.e = 0xD8;
        self.h = 0x01; self.l = 0x4D;
        self.sp = 0xFFFE;
        self.pc = 0x0100; // start of cartridge entry point (after boot ROM)
        self.ime = false;
    }

    pub fn step(self: *Cpu, mmu: *MMU) u32 {
        // Very stubby: fetch a byte and treat it as NOP. Return cycles consumed.
        _ = mmu.read8(self.pc);
        self.pc +%= 1;
        return 4; // NOP cycles
    }
};
