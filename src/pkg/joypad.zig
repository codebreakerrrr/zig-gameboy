const interrupt = @import("interrupt.zig");

pub const Button = enum { Right, Left, Up, Down, A, B, Select, Start };

pub const Joypad = struct {
    sel_buttons: bool = true, // bit 5
    sel_dpad: bool = true,    // bit 4

    right: bool = false,
    left: bool = false,
    up: bool = false,
    down: bool = false,
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,

    pub fn setButton(self: *Joypad, btn: Button, pressed: bool) bool {
        switch (btn) {
            .Right => self.right = pressed,
            .Left => self.left = pressed,
            .Up => self.up = pressed,
            .Down => self.down = pressed,
            .A => self.a = pressed,
            .B => self.b = pressed,
            .Select => self.select = pressed,
            .Start => self.start = pressed,
        }
        return pressed;
    }

    pub fn writeP1(self: *Joypad, value: u8) void {
        self.sel_buttons = (value & 0x20) != 0;
        self.sel_dpad = (value & 0x10) != 0;
    }

    pub fn readP1(self: *Joypad) u8 {
        var v: u8 = 0xC0;
        if (self.sel_buttons) v |= 0x20;
        if (self.sel_dpad) v |= 0x10;
        var lines: u8 = 0x0F;
        if (!self.sel_buttons) {
            if (self.a)      lines &= ~@as(u8, 1);
            if (self.b)      lines &= ~@as(u8, 1 << 1);
            if (self.select) lines &= ~@as(u8, 1 << 2);
            if (self.start)  lines &= ~@as(u8, 1 << 3);
        }
        if (!self.sel_dpad) {
            if (self.right) lines &= ~@as(u8, 1);
            if (self.left)  lines &= ~@as(u8, 1 << 1);
            if (self.up)    lines &= ~@as(u8, 1 << 2);
            if (self.down)  lines &= ~@as(u8, 1 << 3);
        }
        v |= lines;
        return v;
    }
};
