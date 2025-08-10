# Zig Game Boy (WIP)

A starter Game Boy emulator written in Zig. It opens a window via SDL2, loads a ROM file, and runs a stub emulation loop that shows an animated test pattern. From here, you can implement the CPU, MMU, PPU, timers, input, and audio.

## Features
- SDL2 windowed app with a software RGBA framebuffer
- ROM loader with MBC0/MBC1/MBC3/MBC5 switching (baseline)
- MMU with VRAM/WRAM/OAM/HRAM/IO and IF/IE
- Timers (DIV/TIMA/TMA/TAC) with Timer interrupt
- Joypad register (0xFF00) with keyboard mapping
- PPU (DMG) background rendering, STAT/LY timing, VBlank interrupt
- CPU core scaffold with common ops, interrupts (subset; grows over time)

## Requirements
- Zig 0.13+
- SDL2 installed on your system
  - macOS (Homebrew on Apple Silicon): `brew install sdl2` (headers in `/opt/homebrew/include`)
  - macOS (Homebrew on Intel): `brew install sdl2` (headers in `/usr/local/include`)
  - Linux: install `libsdl2-dev` via your package manager
  - Windows: install SDL2 development libraries and ensure the headers and libs are found

## Build and Run

```
zig build
zig build run -- <path-to-rom.gb>
```

Controls (default):
- D-Pad: Arrow keys
- A: Z
- B: X
- Start: Enter
- Select: Right Shift

Example on macOS:

```
zig build run -- ~/ROMs/Tetris.gb
```

## Next Steps
- Expand CPU opcode coverage (full CB set, all loads/ALU/jumps/stack, DAA, STOP/HALT edge cases)
- Complete PPU: window, sprites/OAM, STAT conditions, and timing precision
- Implement serial and more accurate timer-edge behavior
- Persist save RAM for battery-backed carts
- Optional: audio (APU) and CGB features

## Notes
- This is a WIP scaffold. It renders a test pattern so you can verify the window and texture upload path.
