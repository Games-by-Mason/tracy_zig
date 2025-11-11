# Tracy Zig

[Tracy](https://github.com/wolfpld/tracy) client bindings for marking up your Zig projects.

This library aims to expose all features available in Tracy's C API, including features like GPU zones. For the list of features that have yet to be implemented, see the issue tracker.

## Integration

You can integrate Tracy into your library without forcing it on your downstream users. This allows library developers to use Tracy without inconveniencing an application developer who may not be using it.

This section walks you through the integration. [There are plans to simplify this.](https://github.com/Games-by-Mason/tracy_zig/issues/8)

## Documentation

Generated documentation for the bindings available [here](https://docs.gamesbymason.com/tracy/), you can generate up to date docs yourself with `zig build docs`. For documentation on Tracy, see [upstream](https://github.com/wolfpld/tracy).

### Libraries

To integrate Tracy with your library, just add the Tracy module in your build.zig.

All configuration, including whether Tracy is enabled or disabled, is inherited from the executable. If the executable does not specify a preference, Tracy is disabled. **This means that you can use Tracy in your library without forcing it on your downstream users.**

build.zig:
```zig
const tracy = b.dependency("tracy", .{
    .target = target,
    .optimize = optimize,
});

lib.addImport("tracy", tracy.module("tracy"));
```

foo.zig:
```
const tracy = @import("foo");
```

### Executables

Executables need to advertise whether or not Tracy should be enabled, or it will be implicitly disabled. Here's the recommended approach.

build.zig:
```zig
// Allow the user to enable or disable Tracy support with a build flag
const tracy_enabled = b.option(
    bool,
    "tracy",
    "Build with Tracy support.",
) orelse false;

// Get the Tracy dependency
const tracy = b.dependency("tracy", .{
    .target = target,
    .optimize = optimize,
    // ...
});

// Make Tracy available as an import
exe.root_module.addImport("tracy", tracy.module("tracy"));

// Pick an implementation based on the build flags.
// Don't build both, we don't want to link with Tracy at all unless we intend to enable it.
if (tracy_enabled) {
    // The user asked to enable Tracy, use the real implementation
    exe.root_module.addImport("tracy_impl", tracy.module("tracy_impl_enabled"));
} else {
    // The user asked to disable Tracy, use the dummy implementation
    exe.root_module.addImport("tracy_impl", tracy.module("tracy_impl_disabled"));
}
```

main.zig:
```zig
// If `tracy_impl` is not set in your root file, Tracy integration will be disabled.
pub const tracy_impl = @import("tracy_impl");

// You can optionally configure Tracy by setting `tracy_options` in your root file.
pub const tracy = @import("tracy");
pub const tracy_options: tracy.Options = .{
    .on_demand = false,
    .no_broadcast = false,
    .only_localhost = false,
    .only_ipv4 = false,
    .delayed_init = false,
    .manual_lifetime = false,
    .verbose = false,
    .data_port = null,
    .broadcast_port = null,
    .default_callstack_depth = 0,
};
```

## Mark Up

You can mark CPU zones with the following code, see the source for more options:
```zig
fn foo() void {
    const zone = Zone.begin(.{
        .name = "Do some work",
        .src = @src(),
        .color = .tomato,
    });
    defer zone.end();
    // Do some work
}
```

You may also wrap your Zig allocators with an allocator that reports allocations to Tracy:
```zig
var tracy_allocator: tracy.Allocator = .{ .parent = gpa.allocator() };
const allocator = tracy_allocator.allocator();
```

You can write your logs to Tracy with:
```zig
tracy.message(.{
    .text = "Hello, world!",
    .color = .light_green,
});
```

For more advanced use cases, including GPU zones and frame images, see `src/root.zig` and [Tracy's documentation (PDF)](https://github.com/wolfpld/tracy/releases/latest/download/tracy.pdf).

## Where do I get the actual profiler?

This package builds the client for integrating the [Tracy](https://github.com/wolfpld/tracy) profiler into your application. It does not build the profiler GUI that you run as a separate process.

To get the profiler, first check which version these bindings are targeting in `build.zig.zon`. Then either download [download](https://github.com/wolfpld/tracy/releases) that build of the profiler, or build it yourself via the official build instructions.

Tips on building the profiler:
- Read Tracy's [manual](https://github.com/wolfpld/tracy/releases/latest/download/tracy.pdf)
- If the Wayland build fails, use `-DLEGACY=1` to use X11 instead
- If LLVM lto fails, try gcc/g++

## Upgrading Tracy

To upgrade Tracy, just update the version listed in `build.zig.zon`.
