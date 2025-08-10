# Zig Game Boy (WIP)

A starter Game Boy emulator written in Zig. It opens a window via SDL2, loads a ROM file, and runs a stub emulation loop that shows an animated test pattern. From here, you can implement the CPU, MMU, PPU, timers, input, and audio.

## Features
- SDL2 windowed app with a software RGBA framebuffer
- ROM loader and basic cartridge struct
- Emulator skeleton with a `step()` loop and `framebuffer()`

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

Example on macOS:

```
zig build run -- ~/ROMs/Tetris.gb
```

## Next Steps
- Implement the LR35902 CPU (Z80-ish) with instruction decoding and flags
- Add a memory bus and MMU: ROM, VRAM, WRAM, OAM, HRAM, IO regs, interrupts
- Implement PPU pipeline (modes, OAM scan, tile fetch, FIFOs) and LCD timings
- Add joypad input mapping and key handling
- Implement timers and DIV/TIMA behavior
- Optional: audio (APU), save file support (battery-backed RAM), MBCs

## Notes
- This is a WIP scaffold. It renders a test pattern so you can verify the window and texture upload path.
