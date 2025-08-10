const std = @import("std");
const Mmu = @import("mmu.zig").Mmu;
const interrupt = @import("interrupt.zig");

const Flag = struct {
	const Z: u8 = 7;
	const N: u8 = 6;
	const H: u8 = 5;
	const C: u8 = 4;
};

pub const Cpu = struct {
	// Registers
	a: u8 = 0x01,
	f: u8 = 0xB0,
	b: u8 = 0x00,
	c: u8 = 0x13,
	d: u8 = 0x00,
	e: u8 = 0xD8,
	h: u8 = 0x01,
	l: u8 = 0x4D,

	sp: u16 = 0xFFFE,
	pc: u16 = 0x0100,

	ime: bool = false,
	ime_pending: bool = false,
	halted: bool = false,

	mmu: *Mmu,

	pub fn init(mmu: *Mmu) Cpu {
		return .{ .mmu = mmu };
	}

	inline fn setFlag(self: *Cpu, bit: u8, set: bool) void {
		if (set) self.f |= (1 << bit) else self.f &= ~@as(u8, 1 << bit);
		self.f &= 0xF0;
	}
	inline fn getFlag(self: *const Cpu, bit: u8) bool {
		return (self.f & (1 << bit)) != 0;
	}

	inline fn getAF(self: *const Cpu) u16 { return (@as(u16, self.a) << 8) | self.f; }
	inline fn getBC(self: *const Cpu) u16 { return (@as(u16, self.b) << 8) | self.c; }
	inline fn getDE(self: *const Cpu) u16 { return (@as(u16, self.d) << 8) | self.e; }
	inline fn getHL(self: *const Cpu) u16 { return (@as(u16, self.h) << 8) | self.l; }
	inline fn setAF(self: *Cpu, v: u16) void { self.a = @intCast(v >> 8); self.f = @intCast(v & 0xF0); }
	inline fn setBC(self: *Cpu, v: u16) void { self.b = @intCast(v >> 8); self.c = @intCast(v & 0xFF); }
	inline fn setDE(self: *Cpu, v: u16) void { self.d = @intCast(v >> 8); self.e = @intCast(v & 0xFF); }
	inline fn setHL(self: *Cpu, v: u16) void { self.h = @intCast(v >> 8); self.l = @intCast(v & 0xFF); }

	inline fn fetch8(self: *Cpu) u8 {
		const v = self.mmu.read8(self.pc);
		self.pc +%= 1;
		return v;
	}
	inline fn fetch16(self: *Cpu) u16 {
		const lo = self.fetch8();
		const hi = self.fetch8();
		return (@as(u16, hi) << 8) | lo;
	}

	inline fn addSigned8(base: u16, off: i8) u16 {
		const ext: u16 = @bitCast(@as(i16, off));
		return base +% ext;
	}

	fn serviceInterrupts(self: *Cpu) ?u32 {
		const ie = self.mmu.ie;
		const ifl = self.mmu.io[0x0F];
		const pending: u8 = ie & ifl;
		if (!self.ime and !self.halted) return null;
		if (pending == 0) return null;

		self.halted = false;
		if (!self.ime) return null;

		self.ime = false;
		inline for (.{ interrupt.IF_VBLANK, interrupt.IF_STAT, interrupt.IF_TIMER, interrupt.IF_SERIAL, interrupt.IF_JOYPAD }) |bit_idx| {
			const mask = @as(u8, 1) << bit_idx;
			if ((pending & mask) != 0) {
				self.mmu.io[0x0F] &= ~mask;
				const vec: u16 = switch (bit_idx) {
					interrupt.IF_VBLANK => 0x0040,
					interrupt.IF_STAT => 0x0048,
					interrupt.IF_TIMER => 0x0050,
					interrupt.IF_SERIAL => 0x0058,
					interrupt.IF_JOYPAD => 0x0060,
					else => 0x0040,
				};
				self.push16(self.pc);
				self.pc = vec;
				return 20;
			}
		}
		return null;
	}

	inline fn push16(self: *Cpu, v: u16) void {
		self.sp -%= 1; self.mmu.write8(self.sp, @intCast(v >> 8));
		self.sp -%= 1; self.mmu.write8(self.sp, @intCast(v & 0xFF));
	}
	inline fn pop16(self: *Cpu) u16 {
		const lo = self.mmu.read8(self.sp); self.sp +%= 1;
		const hi = self.mmu.read8(self.sp); self.sp +%= 1;
		return (@as(u16, hi) << 8) | lo;
	}

	pub fn step(self: *Cpu) u32 {
		if (self.ime_pending) { self.ime = true; self.ime_pending = false; }

		if (self.halted) {
			if ((self.mmu.ie & self.mmu.io[0x0F]) != 0) self.halted = false;
			if (self.serviceInterrupts()) |cy| return cy;
			return 4;
		}

		if (self.serviceInterrupts()) |cy| return cy;

		const op = self.fetch8();
		return switch (op) {
			0x00 => 4, // NOP

			// LD r, n
			0x06,0x0E,0x16,0x1E,0x26,0x2E => blk: {
				const n = self.fetch8();
				switch (op) {
					0x06 => self.b = n,
					0x0E => self.c = n,
					0x16 => self.d = n,
					0x1E => self.e = n,
					0x26 => self.h = n,
					0x2E => self.l = n,
					else => {},
				}
				break :blk 8;
			},
			0x3E => blk: { self.a = self.fetch8(); break :blk 8; },

			// LD A, r and memory forms
			0x7F => 4,
			0x78 => blk: { self.a = self.b; break :blk 4; },
			0x79 => blk: { self.a = self.c; break :blk 4; },
			0x7A => blk: { self.a = self.d; break :blk 4; },
			0x7B => blk: { self.a = self.e; break :blk 4; },
			0x7C => blk: { self.a = self.h; break :blk 4; },
			0x7D => blk: { self.a = self.l; break :blk 4; },
			0x0A => blk: { self.a = self.mmu.read8(self.getBC()); break :blk 8; },
			0x1A => blk: { self.a = self.mmu.read8(self.getDE()); break :blk 8; },
			0xFA => blk: { const a = self.fetch16(); self.a = self.mmu.read8(a); break :blk 16; },

			// LD (r16), A and variants
			0x02 => blk: { self.mmu.write8(self.getBC(), self.a); break :blk 8; },
			0x12 => blk: { self.mmu.write8(self.getDE(), self.a); break :blk 8; },
			0xEA => blk: { const a = self.fetch16(); self.mmu.write8(a, self.a); break :blk 16; },
			0x77 => blk: { self.mmu.write8(self.getHL(), self.a); break :blk 8; },
			0x36 => blk: { const n = self.fetch8(); self.mmu.write8(self.getHL(), n); break :blk 12; },

			// LDH and IO via C
			0xE0 => blk: { const a8 = self.fetch8(); self.mmu.write8(0xFF00 + @as(u16, a8), self.a); break :blk 12; },
			0xF0 => blk: { const a8 = self.fetch8(); self.a = self.mmu.read8(0xFF00 + @as(u16, a8)); break :blk 12; },
			0xE2 => blk: { self.mmu.write8(0xFF00 + @as(u16, self.c), self.a); break :blk 8; },
			0xF2 => blk: { self.a = self.mmu.read8(0xFF00 + @as(u16, self.c)); break :blk 8; },

			// INC/DEC 8-bit
			0x04,0x0C,0x14,0x1C,0x24,0x2C,0x3C => blk: {
				const v: *u8 = switch (op) {
					0x04 => &self.b, 0x0C => &self.c, 0x14 => &self.d, 0x1C => &self.e,
					0x24 => &self.h, 0x2C => &self.l, 0x3C => &self.a, else => unreachable,
				};
				const res = v.* +% 1;
				self.setFlag(Flag.Z, res == 0);
				self.setFlag(Flag.N, false);
				self.setFlag(Flag.H, (v.* & 0x0F) == 0x0F);
				v.* = res;
				break :blk 4;
			},
			0x05,0x0D,0x15,0x1D,0x25,0x2D,0x3D => blk: {
				const v: *u8 = switch (op) {
					0x05 => &self.b, 0x0D => &self.c, 0x15 => &self.d, 0x1D => &self.e,
					0x25 => &self.h, 0x2D => &self.l, 0x3D => &self.a, else => unreachable,
				};
				const res = v.* -% 1;
				self.setFlag(Flag.Z, res == 0);
				self.setFlag(Flag.N, true);
				self.setFlag(Flag.H, (v.* & 0x0F) == 0x00);
				v.* = res;
				break :blk 4;
			},

			// 16-bit INC/DEC
			0x03 => blk: { self.setBC(self.getBC() +% 1); break :blk 8; },
			0x13 => blk: { self.setDE(self.getDE() +% 1); break :blk 8; },
			0x23 => blk: { self.setHL(self.getHL() +% 1); break :blk 8; },
			0x33 => blk: { self.sp +%= 1; break :blk 8; },
			0x0B => blk: { self.setBC(self.getBC() -% 1); break :blk 8; },
			0x1B => blk: { self.setDE(self.getDE() -% 1); break :blk 8; },
			0x2B => blk: { self.setHL(self.getHL() -% 1); break :blk 8; },
			0x3B => blk: { self.sp -%= 1; break :blk 8; },

			// ADD/ADC to A
			0x80...0x87 => blk: { const v = self.readR(op & 7); self.addA(v, false); break :blk if ((op & 7) == 6) 8 else 4; },
			0xC6 => blk: { const n = self.fetch8(); self.addA(n, false); break :blk 8; },
			0x88...0x8F => blk: { const v = self.readR(op & 7); self.addA(v, true); break :blk if ((op & 7) == 6) 8 else 4; },
			0xCE => blk: { const n = self.fetch8(); self.addA(n, true); break :blk 8; },

			// SUB/SBC
			0x90...0x97 => blk: { const v = self.readR(op & 7); self.subA(v, false); break :blk if ((op & 7) == 6) 8 else 4; },
			0xD6 => blk: { const n = self.fetch8(); self.subA(n, false); break :blk 8; },
			0x98...0x9F => blk: { const v = self.readR(op & 7); self.subA(v, true); break :blk if ((op & 7) == 6) 8 else 4; },
			0xDE => blk: { const n = self.fetch8(); self.subA(n, true); break :blk 8; },

			// AND/OR/XOR
			0xA0...0xA7 => blk: { const v = self.readR(op & 7); self.andA(v); break :blk if ((op & 7) == 6) 8 else 4; },
			0xE6 => blk: { const n = self.fetch8(); self.andA(n); break :blk 8; },
			0xB0...0xB7 => blk: { const v = self.readR(op & 7); self.orA(v); break :blk if ((op & 7) == 6) 8 else 4; },
			0xF6 => blk: { const n = self.fetch8(); self.orA(n); break :blk 8; },
			0xA8...0xAF => blk: { const v = self.readR(op & 7); self.xorA(v); break :blk if ((op & 7) == 6) 8 else 4; },
			0xEE => blk: { const n = self.fetch8(); self.xorA(n); break :blk 8; },

			// CP
			0xB8...0xBF => blk: { const v = self.readR(op & 7); self.cpA(v); break :blk if ((op & 7) == 6) 8 else 4; },
			0xFE => blk: { const n = self.fetch8(); self.cpA(n); break :blk 8; },

			// HL auto inc/dec loads
			0x22 => blk: { const hl = self.getHL(); self.mmu.write8(hl, self.a); self.setHL(hl +% 1); break :blk 8; },
			0x2A => blk: { const hl = self.getHL(); self.a = self.mmu.read8(hl); self.setHL(hl +% 1); break :blk 8; },
			0x32 => blk: { const hl = self.getHL(); self.mmu.write8(hl, self.a); self.setHL(hl -% 1); break :blk 8; },
			0x3A => blk: { const hl = self.getHL(); self.a = self.mmu.read8(hl); self.setHL(hl -% 1); break :blk 8; },

			// 16-bit loads
			0x01 => blk: { const n = self.fetch16(); self.setBC(n); break :blk 12; },
			0x11 => blk: { const n = self.fetch16(); self.setDE(n); break :blk 12; },
			0x21 => blk: { const n = self.fetch16(); self.setHL(n); break :blk 12; },
			0x31 => blk: { const n = self.fetch16(); self.sp = n; break :blk 12; },

			// Stack
			0xF5 => blk: { self.push16(self.getAF()); break :blk 16; },
			0xC5 => blk: { self.push16(self.getBC()); break :blk 16; },
			0xD5 => blk: { self.push16(self.getDE()); break :blk 16; },
			0xE5 => blk: { self.push16(self.getHL()); break :blk 16; },
			0xF1 => blk: { const v = self.pop16(); self.setAF(v & 0xFFF0); break :blk 12; },
			0xC1 => blk: { const v = self.pop16(); self.setBC(v); break :blk 12; },
			0xD1 => blk: { const v = self.pop16(); self.setDE(v); break :blk 12; },
			0xE1 => blk: { const v = self.pop16(); self.setHL(v); break :blk 12; },

			// Jumps/Calls/Returns
			0xC3 => blk: { const a = self.fetch16(); self.pc = a; break :blk 16; },
			0x18 => blk: { const e: i8 = @bitCast(self.fetch8()); self.pc = addSigned8(self.pc, e); break :blk 12; },
			0x20 => blk: {
				const e: i8 = @bitCast(self.fetch8());
				if (!self.getFlag(Flag.Z)) { self.pc = addSigned8(self.pc, e); break :blk 12; } else break :blk 8;
			},
			0x28 => blk: {
				const e: i8 = @bitCast(self.fetch8());
				if (self.getFlag(Flag.Z)) { self.pc = addSigned8(self.pc, e); break :blk 12; } else break :blk 8;
			},
			0x30 => blk: {
				const e: i8 = @bitCast(self.fetch8());
				if (!self.getFlag(Flag.C)) { self.pc = addSigned8(self.pc, e); break :blk 12; } else break :blk 8;
			},
			0x38 => blk: {
				const e: i8 = @bitCast(self.fetch8());
				if (self.getFlag(Flag.C)) { self.pc = addSigned8(self.pc, e); break :blk 12; } else break :blk 8;
			},
			0xCD => blk: { const a = self.fetch16(); self.push16(self.pc); self.pc = a; break :blk 24; },
			0xC9 => blk: { self.pc = self.pop16(); break :blk 16; },
			0xC0 => blk: { if (!self.getFlag(Flag.Z)) { self.pc = self.pop16(); break :blk 20; } else break :blk 8; },
			0xC8 => blk: { if (self.getFlag(Flag.Z)) { self.pc = self.pop16(); break :blk 20; } else break :blk 8; },
			0xD0 => blk: { if (!self.getFlag(Flag.C)) { self.pc = self.pop16(); break :blk 20; } else break :blk 8; },
			0xD8 => blk: { if (self.getFlag(Flag.C)) { self.pc = self.pop16(); break :blk 20; } else break :blk 8; },
			0xD9 => blk: { self.pc = self.pop16(); self.ime = true; break :blk 16; },

			// RST
			0xC7,0xCF,0xD7,0xDF,0xE7,0xEF,0xF7,0xFF => blk: {
				const vec: u16 = switch (op) {
					0xC7 => 0x00, 0xCF => 0x08, 0xD7 => 0x10, 0xDF => 0x18,
					0xE7 => 0x20, 0xEF => 0x28, 0xF7 => 0x30, 0xFF => 0x38, else => 0,
				};
				self.push16(self.pc);
				self.pc = vec;
				break :blk 16;
			},

			// EI/DI/HALT
			0xFB => blk: { self.ime_pending = true; break :blk 4; },
			0xF3 => blk: { self.ime = false; self.ime_pending = false; break :blk 4; },
			0x76 => blk: { self.halted = true; break :blk 4; },

			// DAA / CPL / SCF / CCF / STOP
			0x27 => blk: { self.execDAA(); break :blk 4; },
			0x2F => blk: { self.a = ~self.a; self.setFlag(Flag.N, true); self.setFlag(Flag.H, true); break :blk 4; },
			0x37 => blk: { self.setFlag(Flag.N, false); self.setFlag(Flag.H, false); self.setFlag(Flag.C, true); break :blk 4; },
			0x3F => blk: { self.setFlag(Flag.N, false); self.setFlag(Flag.H, false); self.setFlag(Flag.C, !self.getFlag(Flag.C)); break :blk 4; },
			// STOP: consume one byte and act as no-op for now
			0x10 => blk: { _ = self.fetch8(); break :blk 4; },

			// CB prefix
			0xCB => self.execCB(),

			else => 4,
		};
	}

	fn readR(self: *Cpu, idx: u8) u8 {
		return switch (idx) {
			0 => self.b, 1 => self.c, 2 => self.d, 3 => self.e, 4 => self.h, 5 => self.l, 6 => self.mmu.read8(self.getHL()), 7 => self.a, else => 0,
		};
	}
	fn writeR(self: *Cpu, idx: u8, v: u8) void {
		switch (idx) {
			0 => self.b = v, 1 => self.c = v, 2 => self.d = v, 3 => self.e = v, 4 => self.h = v, 5 => self.l = v, 6 => self.mmu.write8(self.getHL(), v), 7 => self.a = v, else => {},
		}
	}

	fn addA(self: *Cpu, v: u8, with_carry: bool) void {
		const a = self.a;
		const c: u16 = if (with_carry and self.getFlag(Flag.C)) @as(u16, 1) else @as(u16, 0);
		const res: u16 = @as(u16, a) + @as(u16, v) + c;
		self.a = @intCast(res & 0xFF);
		self.setFlag(Flag.Z, self.a == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, ((a & 0x0F) + (v & 0x0F) + @as(u8, @intCast(c))) > 0x0F);
		self.setFlag(Flag.C, res > 0xFF);
	}
	fn subA(self: *Cpu, v: u8, with_carry: bool) void {
		const a = self.a;
		const c: u8 = if (with_carry and self.getFlag(Flag.C)) 1 else 0;
		const res_i: i16 = @as(i16, a) - @as(i16, v) - @as(i16, c);
		const res: u8 = @intCast(res_i & 0xFF);
		self.a = res;
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, true);
		self.setFlag(Flag.H, ((a & 0x0F) < ((v & 0x0F) + c)));
		self.setFlag(Flag.C, @as(i16, a) < (@as(i16, v) + @as(i16, c)));
	}
	fn andA(self: *Cpu, v: u8) void {
		self.a &= v;
		self.setFlag(Flag.Z, self.a == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, true);
		self.setFlag(Flag.C, false);
	}
	fn orA(self: *Cpu, v: u8) void {
		self.a |= v;
		self.setFlag(Flag.Z, self.a == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, false);
	}
	fn xorA(self: *Cpu, v: u8) void {
		self.a ^= v;
		self.setFlag(Flag.Z, self.a == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, false);
	}
	fn cpA(self: *Cpu, v: u8) void {
		const a = self.a;
		const res: i16 = @as(i16, a) - @as(i16, v);
		self.setFlag(Flag.Z, (@as(u8, @intCast(res & 0xFF))) == 0);
		self.setFlag(Flag.N, true);
		self.setFlag(Flag.H, (a & 0x0F) < (v & 0x0F));
		self.setFlag(Flag.C, a < v);
	}

	fn execCB(self: *Cpu) u32 {
		const op = self.fetch8();
		const idx = op & 0x07;
		switch (op & 0xF8) {
			0x00,0x08,0x10,0x18,0x20,0x28,0x30,0x38 => {
				const v = self.readR(idx);
				const res = switch (op & 0xF8) {
					0x00 => self.rlc(v),
					0x08 => self.rrc(v),
					0x10 => self.rl(v),
					0x18 => self.rr(v),
					0x20 => self.sla(v),
					0x28 => self.sra(v),
					0x30 => self.swap(v),
					0x38 => self.srl(v),
					else => v,
				};
				self.writeR(idx, res);
				return if (idx == 6) 16 else 8;
			},
			0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78 => {
				const b: u3 = @intCast((op >> 3) & 0x07);
				const v = self.readR(idx);
				const z = ((v >> b) & 1) == 0;
				self.setFlag(Flag.Z, z);
				self.setFlag(Flag.N, false);
				self.setFlag(Flag.H, true);
				return if (idx == 6) 12 else 8;
			},
			0x80,0x88,0x90,0x98,0xA0,0xA8,0xB0,0xB8 => {
				const b: u3 = @intCast((op >> 3) & 0x07);
				var v = self.readR(idx);
				v &= ~(@as(u8, 1) << b);
				self.writeR(idx, v);
				return if (idx == 6) 16 else 8;
			},
			0xC0,0xC8,0xD0,0xD8,0xE0,0xE8,0xF0,0xF8 => {
				const b: u3 = @intCast((op >> 3) & 0x07);
				var v = self.readR(idx);
				v |= (@as(u8, 1) << b);
				self.writeR(idx, v);
				return if (idx == 6) 16 else 8;
			},
			else => return 8,
		}
	}

	fn rlc(self: *Cpu, v: u8) u8 {
		const out_c = (v >> 7) & 1;
		const res = (v << 1) | out_c;
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn rrc(self: *Cpu, v: u8) u8 {
		const out_c = v & 1;
		const res = (v >> 1) | (out_c << 7);
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn rl(self: *Cpu, v: u8) u8 {
		const carry_in: u8 = if (self.getFlag(Flag.C)) 1 else 0;
		const out_c = (v >> 7) & 1;
		const res = (v << 1) | carry_in;
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn rr(self: *Cpu, v: u8) u8 {
		const carry_in: u8 = if (self.getFlag(Flag.C)) 1 else 0;
		const out_c = v & 1;
		const res = (v >> 1) | (carry_in << 7);
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn sla(self: *Cpu, v: u8) u8 {
		const out_c = (v >> 7) & 1;
		const res = v << 1;
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn sra(self: *Cpu, v: u8) u8 {
		const out_c = v & 1;
		const res = (v & 0x80) | (v >> 1);
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn srl(self: *Cpu, v: u8) u8 {
		const out_c = v & 1;
		const res = v >> 1;
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, out_c == 1);
		return res;
	}
	fn swap(self: *Cpu, v: u8) u8 {
		const res = (v << 4) | (v >> 4);
		self.setFlag(Flag.Z, res == 0);
		self.setFlag(Flag.N, false);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, false);
		return res;
	}

	fn execDAA(self: *Cpu) void {
		var a = self.a;
		var adjust: u8 = 0;
		var set_c = self.getFlag(Flag.C);
		if (!self.getFlag(Flag.N)) {
			if (self.getFlag(Flag.H) or ((a & 0x0F) > 9)) adjust += 0x06;
			if (self.getFlag(Flag.C) or (a > 0x99)) { adjust += 0x60; set_c = true; }
			a +%= adjust;
		} else {
			if (self.getFlag(Flag.H)) adjust += 0x06;
			if (self.getFlag(Flag.C)) { adjust += 0x60; }
			a -%= adjust;
		}
		self.a = a;
		self.setFlag(Flag.Z, self.a == 0);
		self.setFlag(Flag.H, false);
		self.setFlag(Flag.C, set_c);
	}
};
