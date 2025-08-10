const std = @import("std");

pub const MbcType = enum { none, mbc1, mbc3, mbc5 };

pub const Cartridge = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    save_path: []u8 = &[_]u8{},
    title: [16]u8 = [_]u8{0} ** 16,
    mbc: MbcType = .none,
    has_ram: bool = false,
    has_battery: bool = false,

    ram_enabled: bool = false,
    rom_bank: u16 = 1,
    ram_bank: u8 = 0,
    banking_mode: u8 = 0,
    ext_ram: []u8 = &[_]u8{},

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Cartridge {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const stat = try file.stat();
        const bytes = try allocator.alloc(u8, @intCast(stat.size));
        errdefer allocator.free(bytes);
        const read = try file.readAll(bytes);
        if (read != bytes.len) return error.UnexpectedEof;
        var cart = try Cartridge.load(allocator, bytes);
        // Build save path alongside ROM
        cart.save_path = try deriveSavePath(allocator, path);
        // If battery-backed and ext RAM allocated, try to load existing save
        if (cart.has_battery and cart.ext_ram.len > 0) {
            if (std.fs.cwd().openFile(cart.save_path, .{})) |sav| {
                defer sav.close();
                const s = try sav.stat();
                const to_read = @min(@as(usize, @intCast(s.size)), cart.ext_ram.len);
                _ = try sav.readAll(cart.ext_ram[0..to_read]);
            } else |_| {}
        }
        return cart;
    }

    pub fn load(allocator: std.mem.Allocator, bytes: []const u8) !Cartridge {
        var cart = Cartridge{
            .allocator = allocator,
            .data = bytes,
        };
        if (bytes.len >= 0x150) {
            const cart_type = bytes[0x0147];
            cart.mbc = switch (cart_type) {
                0x00 => .none,
                0x01, 0x02, 0x03 => .mbc1,
                0x0F, 0x10, 0x11, 0x12, 0x13 => .mbc3,
                0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E => .mbc5,
                else => .none,
            };
            cart.has_ram = switch (cart_type) { 0x02,0x03,0x08,0x09,0x10,0x12,0x13,0x1A,0x1B,0x1D,0x1E => true, else => false };
            cart.has_battery = switch (cart_type) { 0x03,0x06,0x09,0x0D,0x0F,0x10,0x13,0x1B,0x1E => true, else => false };
            var i: usize = 0;
            while (i < 16 and 0x0134 + i < bytes.len) : (i += 1) {
                const b = bytes[0x0134 + i];
                cart.title[i] = if (b >= 0x20 and b <= 0x7E) b else 0;
            }
            const ram_size_code = if (0x0149 < bytes.len) bytes[0x0149] else 0;
            const ram_len: usize = switch (ram_size_code) { 0x00 => 0, 0x01 => 2*1024, 0x02 => 8*1024, 0x03 => 32*1024, 0x04 => 128*1024, 0x05 => 64*1024, else => 0 };
            if (ram_len > 0) {
                cart.ext_ram = try allocator.alloc(u8, ram_len);
                @memset(cart.ext_ram, 0);
            }
        }
        return cart;
    }

    pub fn deinit(self: *Cartridge) void {
        // Persist save RAM if battery-backed
        if (self.has_battery and self.ext_ram.len > 0 and self.save_path.len > 0) {
            if (std.fs.cwd().createFile(self.save_path, .{ .read = true, .truncate = true })) |sav| {
                defer sav.close();
                _ = sav.writeAll(self.ext_ram) catch {};
            } else |_| {}
        }
        if (self.ext_ram.len > 0) self.allocator.free(self.ext_ram);
        if (self.data.len > 0) self.allocator.free(@constCast(self.data));
        if (self.save_path.len > 0) self.allocator.free(self.save_path);
    }

    fn deriveSavePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        // Replace .gb/.gbc (case-insensitive) with .sav; else append .sav
        const ext = std.fs.path.extension(path); // includes leading '.' if present, else ""
        const is_eq = struct {
            fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
                if (a.len != b.len) return false;
                var i: usize = 0;
                while (i < a.len) : (i += 1) {
                    if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[i])) return false;
                }
                return true;
            }
        }.eqIgnoreCase;
        if (is_eq(ext, ".gb")) {
            const n = path.len - ext.len;
            return try std.fmt.allocPrint(allocator, "{s}.sav", .{path[0..n]});
        } else if (is_eq(ext, ".gbc")) {
            const n = path.len - ext.len;
            return try std.fmt.allocPrint(allocator, "{s}.sav", .{path[0..n]});
        } else {
            return try std.fmt.allocPrint(allocator, "{s}.sav", .{path});
        }
    }

    pub fn romRead(self: *const Cartridge, addr: u16) u8 {
        const a = addr;
        if (a < 0x4000) return if (a < self.data.len) self.data[a] else 0xFF;
        if (a < 0x8000) {
            const bank: usize = switch (self.mbc) {
                .none => 1,
                .mbc1 => @max(@as(usize, @intCast(self.rom_bank & 0x1F)), 1) | (if (self.banking_mode == 0) (@as(usize, self.ram_bank) << 5) else 0),
                .mbc3 => @max(@as(usize, @intCast(self.rom_bank & 0x7F)), 1),
                .mbc5 => @as(usize, self.rom_bank & 0x1FF),
            };
            const offset = (bank % @as(usize, @max(1, self.data.len / 0x4000))) * 0x4000 + (a - 0x4000);
            return if (offset < self.data.len) self.data[offset] else 0xFF;
        }
        return 0xFF;
    }

    pub fn extRamRead(self: *const Cartridge, addr: u16) u8 {
        if (!self.ram_enabled or self.ext_ram.len == 0) return 0xFF;
        const bank_size: usize = 0x2000;
        var bank_index: usize = 0;
        switch (self.mbc) {
            .mbc1 => bank_index = if (self.banking_mode == 1) @as(usize, self.ram_bank & 0x03) else 0,
            .mbc3 => bank_index = @as(usize, self.ram_bank & 0x03),
            .mbc5 => bank_index = @as(usize, self.ram_bank & 0x0F),
            else => {},
        }
        const offset = bank_index * bank_size + (@as(usize, addr) - 0xA000);
        return if (offset < self.ext_ram.len) self.ext_ram[offset] else 0xFF;
    }

    pub fn extRamWrite(self: *Cartridge, addr: u16, value: u8) void {
        if (!self.ram_enabled or self.ext_ram.len == 0) return;
        const bank_size: usize = 0x2000;
        var bank_index: usize = 0;
        switch (self.mbc) {
            .mbc1 => bank_index = if (self.banking_mode == 1) @as(usize, self.ram_bank & 0x03) else 0,
            .mbc3 => bank_index = @as(usize, self.ram_bank & 0x03),
            .mbc5 => bank_index = @as(usize, self.ram_bank & 0x0F),
            else => {},
        }
        const offset = bank_index * bank_size + (@as(usize, addr) - 0xA000);
        if (offset < self.ext_ram.len) self.ext_ram[offset] = value;
    }

    pub fn write(self: *Cartridge, addr: u16, value: u8) void {
        const a = addr;
        switch (self.mbc) {
            .none => {},
            .mbc1 => {
                if (a < 0x2000) {
                    self.ram_enabled = (value & 0x0F) == 0x0A;
                } else if (a < 0x4000) {
                    var v = value & 0x1F;
                    if (v == 0) v = 1;
                    self.rom_bank = (self.rom_bank & ~@as(u16, 0x1F)) | v;
                } else if (a < 0x6000) {
                    self.ram_bank = value & 0x03;
                } else {
                    self.banking_mode = value & 0x01;
                }
            },
            .mbc3 => {
                if (a < 0x2000) {
                    self.ram_enabled = (value & 0x0F) == 0x0A;
                } else if (a < 0x4000) {
                    const v = value & 0x7F;
                    self.rom_bank = if (v == 0) 1 else v;
                } else if (a < 0x6000) {
                    self.ram_bank = value; // RTC not implemented
                }
            },
            .mbc5 => {
                if (a < 0x2000) {
                    self.ram_enabled = (value & 0x0F) == 0x0A;
                } else if (a < 0x3000) {
                    self.rom_bank = (self.rom_bank & 0x100) | value;
                } else if (a < 0x4000) {
                    self.rom_bank = (self.rom_bank & 0x0FF) | (@as(u16, value & 0x01) << 8);
                } else if (a < 0x6000) {
                    self.ram_bank = value & 0x0F;
                }
            },
        }
    }
};
