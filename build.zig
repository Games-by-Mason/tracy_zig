const std = @import("std");

pub fn build(b: *std.Build) void {
    // Get standard build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const optimize_external = switch (optimize) {
        // See https://github.com/Games-by-Mason/tracy_zig/issues/6
        //
        // Once this is resolved, this should be release safe instead.
        .Debug, .ReleaseSafe => .ReleaseFast,
        else => optimize,
    };

    // Build the disabled implementation
    const impl_disabled = b.addModule("tracy_impl_disabled", .{
        .root_source_file = b.path("src/impl_disabled.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library
    const tracy = b.addModule("tracy", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    tracy.addImport("impl_disabled", impl_disabled);

    // Build the enabled implementation
    const impl_enabled = b.addModule("tracy_impl_enabled", .{
        .root_source_file = b.path("src/impl_enabled.zig"),
        .target = target,
        .optimize = optimize,
    });
    impl_enabled.addImport("tracy", tracy);

    const upstream = b.dependency("tracy", .{});
    const lib_tracy = b.addLibrary(.{
        .name = "tracy",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize_external,
        }),
    });
    lib_tracy.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "public/TracyClient.cpp",
            "public/client/TracyProfiler.cpp",
        },
        .flags = &.{},
    });
    lib_tracy.root_module.addCMacro("TRACY_ENABLE", "");
    lib_tracy.addIncludePath(upstream.path("public/tracy"));
    lib_tracy.installHeader(upstream.path("public/tracy/TracyC.h"), "tracy/tracy/TracyC.h");
    const hopt: std.Build.Step.Compile.HeaderInstallation.Directory.Options = .{
        .include_extensions = &.{ ".h", ".hpp" },
    };
    lib_tracy.installHeadersDirectory(upstream.path("public/client"), "tracy/client", hopt);
    lib_tracy.installHeadersDirectory(upstream.path("public/common"), "tracy/common", hopt);
    lib_tracy.linkLibCpp();

    if (target.result.os.tag == .windows) {
        lib_tracy.linkSystemLibrary("Ws2_32");
        lib_tracy.linkSystemLibrary("dbghelp");
    }
    impl_enabled.linkLibrary(lib_tracy);

    // We need an executable to generate docs, but we don't want to use a test executable because
    // "test" ends up in our URLs if we do.
    const docs_exe = b.addExecutable(.{
        .name = "tracy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/docs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const docs = docs_exe.getEmittedDocs();
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build the docs");
    docs_step.dependOn(&install_docs.step);
}
