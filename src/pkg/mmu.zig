const std = @import("std");
const Cartridge = @import("cartridge.zig").Cartridge;

pub const MMU = struct {
    cart: Cartridge,
    wram: [8 * 1024]u8 = [_]u8{0} ** (8 * 1024),
    hram: [127]u8 = [_]u8{0} ** 127,

    pub fn init(cart: Cartridge) MMU {
        return .{ .cart = cart };
    }

    pub fn read8(self: *MMU, addr: u16) u8 {
        const a = addr;
        // extremely simplified mapping: 0x0000-7FFF ROM only
        if (a <= 0x7FFF) {
            if (@as(usize, a) < self.cart.data.len) return self.cart.data[@intCast(a)];
            return 0xFF;
        }
        // TODO: map VRAM, WRAM, IO, etc. For now return open-bus-ish
        return 0xFF;
    }

    pub fn write8(self: *MMU, addr: u16, value: u8) void {
        _ = value;
        const a = addr;
        // TODO: handle writes properly; ignore for now
        _ = self;
        _ = a;
    }
};
