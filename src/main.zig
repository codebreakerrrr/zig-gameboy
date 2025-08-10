const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

const Cartridge = @import("pkg/cartridge.zig").Cartridge;
const Emulator = @import("pkg/emulator.zig").Emulator;
const Renderer = @import("pkg/renderer.zig").Renderer;

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
    defer cart.deinit(allocator);

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
                    // TODO: map keys to joypad
                },
                sdl.SDL_KEYUP => {
                    // TODO: map keys to joypad
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
