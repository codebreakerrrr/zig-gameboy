pub const IF_VBLANK: u8 = 0;
pub const IF_STAT: u8 = 1;
pub const IF_TIMER: u8 = 2;
pub const IF_SERIAL: u8 = 3;
pub const IF_JOYPAD: u8 = 4;

pub inline fn bit(mask_bit: u8) u8 {
    return @as(u8, 1) << mask_bit;
}
