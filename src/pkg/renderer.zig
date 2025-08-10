const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const emu = @import("emulator.zig");

pub const Renderer = struct {
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    texture: *sdl.SDL_Texture,
    scale: i32,

    pub fn init(allocator: std.mem.Allocator, title: []const u8, scale: i32) !Renderer {
        _ = allocator; // not needed for now
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS) != 0) {
            return error.SdlInitFailed;
        }
        errdefer sdl.SDL_Quit();

        const win_w: i32 = @intCast(@as(i32, emu.LCD_WIDTH) * scale);
        const win_h: i32 = @intCast(@as(i32, emu.LCD_HEIGHT) * scale);
        // Ensure C-string for title
        var title_buf: [256]u8 = undefined;
        const c_title = blk: {
            const n = @min(title.len, title_buf.len - 1);
            std.mem.copyForwards(u8, title_buf[0..n], title[0..n]);
            title_buf[n] = 0; // null-terminate
            break :blk &title_buf;
        };
        const window = sdl.SDL_CreateWindow(
            @ptrCast(c_title),
            sdl.SDL_WINDOWPOS_CENTERED,
            sdl.SDL_WINDOWPOS_CENTERED,
            win_w,
            win_h,
            sdl.SDL_WINDOW_SHOWN,
        ) orelse return error.SdlCreateWindowFailed;
        errdefer sdl.SDL_DestroyWindow(window);

        const renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC)
            orelse return error.SdlCreateRendererFailed;
        errdefer sdl.SDL_DestroyRenderer(renderer);

        // We'll upload RGBA8888 pixels
        const texture = sdl.SDL_CreateTexture(
            renderer,
            // ABGR8888 typically matches 0xRRGGBBAA in memory on little-endian
            sdl.SDL_PIXELFORMAT_ABGR8888,
            sdl.SDL_TEXTUREACCESS_STREAMING,
            @intCast(emu.LCD_WIDTH),
            @intCast(emu.LCD_HEIGHT),
        ) orelse return error.SdlCreateTextureFailed;
        errdefer sdl.SDL_DestroyTexture(texture);

        return .{ .window = window, .renderer = renderer, .texture = texture, .scale = scale };
    }

    pub fn deinit(self: *Renderer) void {
        sdl.SDL_DestroyTexture(self.texture);
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    pub fn present(self: *Renderer, fb: []const u32) !void {
        var pitch: i32 = 0;
        var pixels_ptr: ?*anyopaque = null;
        if (sdl.SDL_LockTexture(self.texture, null, &pixels_ptr, &pitch) != 0) return error.SdlLockTextureFailed;
        defer sdl.SDL_UnlockTexture(self.texture);
        // pitch is in bytes
        const dst_row_bytes: usize = @intCast(pitch);
        const src_row_bytes: usize = emu.LCD_WIDTH * @sizeOf(u32);
        var y: usize = 0;
        while (y < emu.LCD_HEIGHT) : (y += 1) {
            const src_row = fb[y * emu.LCD_WIDTH .. y * emu.LCD_WIDTH + emu.LCD_WIDTH];
            const dst_row: [*]u8 = @ptrCast(pixels_ptr.?);
            const dst_off: usize = y * dst_row_bytes;
            std.mem.copyForwards(u8, dst_row[dst_off .. dst_off + src_row_bytes], std.mem.asBytes(src_row));
        }

        _ = sdl.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
        _ = sdl.SDL_RenderClear(self.renderer);
        _ = sdl.SDL_RenderCopy(self.renderer, self.texture, null, null);
        sdl.SDL_RenderPresent(self.renderer);
    }
};
