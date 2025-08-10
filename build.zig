const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-gameboy",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // SDL2 is used for windowing, input, and presenting the framebuffer.
    // On macOS via Homebrew, headers are usually in /opt/homebrew/include (Apple Silicon)
    // or /usr/local/include (Intel). We add both include paths to help Zig find SDL headers.
    exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.linkSystemLibrary("SDL2");
    // Help the linker/runtime find SDL2 dylib on macOS (Homebrew paths)
    exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.addRPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    exe.addRPath(.{ .cwd_relative = "/usr/local/lib" });

    // macOS specifics: ensure we link against the C system lib
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the Game Boy emulator");
    run_step.dependOn(&run_cmd.step);
}
