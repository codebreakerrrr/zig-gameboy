const interrupt = @import("interrupt.zig");

pub const Timer = struct {
    div: u8 = 0,
    tima: u8 = 0,
    tma: u8 = 0,
    tac: u8 = 0,

    div_counter: u32 = 0,
    tima_counter: u32 = 0,

    pub fn reset(self: *Timer) void {
        self.* = .{};
    }

    pub fn step(self: *Timer, cycles: u32) bool {
        self.div_counter += cycles;
        while (self.div_counter >= 256) {
            self.div_counter -= 256;
            self.div +%= 1;
        }
        if ((self.tac & 0x04) != 0) {
            self.tima_counter += cycles;
            const period: u32 = switch (self.tac & 0x03) {
                0 => 1024,
                1 => 16,
                2 => 64,
                3 => 256,
                else => 1024,
            };
            while (self.tima_counter >= period) {
                self.tima_counter -= period;
                if (self.tima == 0xFF) {
                    self.tima = self.tma;
                    return true; // request IF_TIMER
                } else self.tima +%= 1;
            }
        }
        return false;
    }

    pub fn read(self: *Timer, addr: u16) u8 {
        return switch (addr) {
            0xFF04 => self.div,
            0xFF05 => self.tima,
            0xFF06 => self.tma,
            0xFF07 => self.tac | 0xF8,
            else => 0xFF,
        };
    }

    pub fn write(self: *Timer, addr: u16, value: u8) void {
        switch (addr) {
            0xFF04 => { self.div = 0; self.div_counter = 0; },
            0xFF05 => self.tima = value,
            0xFF06 => self.tma = value,
            0xFF07 => self.tac = value & 0x07,
            else => {},
        }
    }
};
