const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

const Cartridge = @import("pkg/cartridge.zig").Cartridge;
const Emulator = @import("pkg/emulator.zig").Emulator;
const Renderer = @import("pkg/renderer.zig").Renderer;
const Joypad = @import("pkg/joypad.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    defer args.deinit();

    // Expect a ROM path as the first arg after program name
    _ = args.next();
    const rom_path = args.next() orelse {
        std.debug.print("Usage: zig-gameboy <path_to_rom.gb>\n", .{});
        return error.InvalidArgs;
    };

    // Load ROM from disk
    const cart = try Cartridge.loadFromFile(allocator, rom_path);

    // Initialize emulator core
    var emu = try Emulator.init(allocator, cart);
    defer emu.deinit(allocator);

    // Init SDL and window/renderer
    var renderer = try Renderer.init(allocator, "Zig Game Boy", 3);
    defer renderer.deinit();

    // Main loop
    var quit = false;
    var last_ticks: u64 = sdl.SDL_GetPerformanceCounter();
    const freq: f64 = @floatFromInt(sdl.SDL_GetPerformanceFrequency());

    while (!quit) {
        // Poll events
        var ev: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&ev) != 0) {
            switch (ev.type) {
                sdl.SDL_QUIT => quit = true,
                sdl.SDL_KEYDOWN => {
                    if (ev.key.keysym.sym == sdl.SDLK_ESCAPE) quit = true;
                    if (mapKey(&emu, ev.key.keysym.sym, true)) {}
                },
                sdl.SDL_KEYUP => {
                    _ = mapKey(&emu, ev.key.keysym.sym, false);
                },
                else => {},
            }
        }

        const now: u64 = sdl.SDL_GetPerformanceCounter();
        const dt_sec: f64 = @as(f64, @floatFromInt(now - last_ticks)) / freq;
        last_ticks = now;

        // Step emulator for approximately dt time (placeholder: fixed steps)
        try emu.step(dt_sec);

        // Present framebuffer
        try renderer.present(emu.framebuffer());

        // Small delay to avoid busy-loop
        sdl.SDL_Delay(1);
    }
}

fn mapKey(emu: *Emulator, sym: sdl.SDL_Keycode, pressed: bool) bool {
    const btn = switch (sym) {
        sdl.SDLK_z => @as(?Joypad.Button, .A),
        sdl.SDLK_x => @as(?Joypad.Button, .B),
        sdl.SDLK_RETURN => .Start,
        sdl.SDLK_RSHIFT => .Select,
        sdl.SDLK_UP => .Up,
        sdl.SDLK_DOWN => .Down,
        sdl.SDLK_LEFT => .Left,
        sdl.SDLK_RIGHT => .Right,
        else => null,
    };
    if (btn) |b| {
        if (emu.mmu.joypad.setButton(b, pressed)) {
            // Request joypad interrupt on press
            emu.mmu.io[0x0F] |= 1 << 4;
        }
        return true;
    }
    return false;
}
