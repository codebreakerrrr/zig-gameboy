const std = @import("std");

pub const Cartridge = struct {
    data: []const u8,

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Cartridge {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const stat = try file.stat();
        const buf = try allocator.alloc(u8, @intCast(stat.size));
        errdefer allocator.free(buf);
        const read = try file.readAll(buf);
        if (read != buf.len) return error.UnexpectedEof;
        return .{ .data = buf };
    }

    pub fn deinit(self: Cartridge, allocator: std.mem.Allocator) void {
        allocator.free(@constCast(self.data));
    }

    pub fn title(self: Cartridge) []const u8 {
        // Game Boy ROM title is typically at 0x0134..0x0143 (varies)
        if (self.data.len < 0x0143) return "";
        return self.data[0x0134..0x0143];
    }
};
