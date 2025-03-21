const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");
const assert = std.debug.assert;
const tracy_zig = @This();

// Set up the implementation based on what's found in root.
const impl_disabled = @import("impl_disabled");
const impl = if (@hasDecl(root, "tracy_impl")) b: {
    // Tracy only supports little endian CPUs
    assert(builtin.cpu.arch.endian() == .little);
    break :b root.tracy_impl;
} else impl_disabled;

// The max callstack depth supported by Tracy.
const max_callstack_depth = 62;

// Expose our global options, and whether or not we're enabled publicly.
pub const Options = struct {
    on_demand: bool = false,
    no_broadcast: bool = false,
    only_localhost: bool = false,
    only_ipv4: bool = false,
    delayed_init: bool = false,
    manual_lifetime: bool = false,
    verbose: bool = false,
    data_port: ?u64 = null,
    broadcast_port: ?u64 = null,
    default_callstack_depth: u6 = 0,
};

fn getOptions() Options {
    const result: Options = if (@hasDecl(root, "tracy_options")) root.tracy_options else .{};
    comptime assert(result.default_callstack_depth <= max_callstack_depth);
    return result;
}

pub const enabled = impl != impl_disabled;
pub const options: Options = getOptions();

// Bindings follow.
pub const SourceLocation = extern struct {
    name: ?[*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: Color,

    pub const InitOptions = struct {
        name: ?[*:0]const u8 = null,
        src: std.builtin.SourceLocation,
        color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };

    pub fn init(comptime opt: InitOptions) *const SourceLocation {
        if (enabled) {
            comptime assert(@sizeOf(@This()) == @sizeOf(impl.c.___tracy_source_location_data));
        }
        return comptime &.{
            .name = opt.name,
            .function = opt.src.fn_name.ptr,
            .file = opt.src.file.ptr,
            .line = opt.src.line,
            .color = opt.color,
        };
    }
};

pub const Zone = struct {
    ctx: if (enabled) impl.c.TracyCZoneCtx else void,

    pub const BeginOptions = struct {
        name: ?[*:0]const u8 = null,
        src: std.builtin.SourceLocation,
        color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        callstack_depth: u6 = options.default_callstack_depth,
    };

    pub inline fn begin(comptime opt: BeginOptions) @This() {
        comptime assert(opt.callstack_depth <= max_callstack_depth);
        if (enabled) {
            return .{
                .ctx = impl.c.___tracy_emit_zone_begin_callstack(
                    @intFromPtr(SourceLocation.init(.{
                        .name = opt.name,
                        .src = opt.src,
                        .color = opt.color,
                    })),
                    opt.callstack_depth,
                    1,
                ),
            };
        } else {
            return .{ .ctx = {} };
        }
    }

    pub inline fn end(self: @This()) void {
        if (enabled) impl.c.___tracy_emit_zone_end(self.ctx);
    }

    pub inline fn text(self: @This(), txt: []const u8) void {
        if (enabled) impl.c.___tracy_emit_zone_text(self.ctx, txt.ptr, txt.len);
    }

    pub inline fn color(self: @This(), col: u32) void {
        if (enabled) impl.c.___tracy_emit_zone_color(self.ctx, col);
    }

    pub inline fn value(self: @This(), val: u64) void {
        if (enabled) impl.c.___tracy_emit_zone_value(self.ctx, val);
    }

    pub inline fn name(self: @This(), txt: []const u8) void {
        if (enabled) impl.c.___tracy_emit_zone_name(self.ctx, txt.ptr, txt.len);
    }
};

pub fn frameMark(name: ?[*:0]const u8) void {
    if (enabled) impl.c.___tracy_emit_frame_mark(name);
}

pub inline fn frameMarkStart(name: [:0]const u8) void {
    if (enabled) impl.c.___tracy_emit_frame_mark_start(name);
}

pub inline fn frameMarkEnd(name: [:0]const u8) void {
    if (enabled) impl.c.___tracy_emit_frame_mark_end(name);
}

pub const GpuQueue = struct {
    pub const InitOptions = struct {
        pub const Flags = packed struct(u8) {
            calibration: bool = false,
            _padding: u7 = 0,
        };
        pub const Type = enum(u8) {
            invalid = 0,
            opengl = 1,
            vulkan = 2,
            opencl = 3,
            direct3d_12 = 4,
            direct3d_11 = 5,
        };
        gpu_time: u64,
        period: f32,
        context: u8,
        flags: Flags = .{},
        type: Type,
        name: ?[]const u8,
    };

    context: if (enabled) u8 else void,

    pub inline fn init(opt: InitOptions) @This() {
        if (enabled) {
            impl.c.___tracy_emit_gpu_new_context_serial(.{
                .gpuTime = @bitCast(opt.gpu_time),
                .period = opt.period,
                .context = opt.context,
                .flags = @bitCast(opt.flags),
                .type = @intFromEnum(opt.type),
            });

            if (opt.name) |name| {
                impl.c.___tracy_emit_gpu_context_name_serial(.{
                    .context = opt.context,
                    .name = name.ptr,
                    .len = @intCast(name.len),
                });
            }
            return .{ .context = opt.context };
        } else {
            return .{ .context = {} };
        }
    }

    pub const BeginZoneOptions = struct {
        loc: *const SourceLocation,
        query_id: u16,
        callstack_depth: u6 = options.default_callstack_depth,
    };

    pub inline fn beginZone(self: @This(), opt: BeginZoneOptions) void {
        assert(opt.callstack_depth <= max_callstack_depth);
        if (enabled) {
            if (opt.callstack_depth > 0) {
                impl.c.___tracy_emit_gpu_zone_begin_callstack_serial(.{
                    .srcloc = @intFromPtr(opt.loc),
                    .queryId = opt.query_id,
                    .context = self.context,
                    .depth = opt.callstack_depth,
                });
            } else {
                impl.c.___tracy_emit_gpu_zone_begin_serial(.{
                    .srcloc = @intFromPtr(opt.loc),
                    .queryId = opt.query_id,
                    .context = self.context,
                });
            }
        }
    }

    pub inline fn endZone(self: @This(), query_id: u16) void {
        if (enabled) impl.c.___tracy_emit_gpu_zone_end_serial(.{
            .queryId = query_id,
            .context = self.context,
        });
    }

    pub const EmitTimeOptions = struct {
        query_id: u16,
        gpu_time: u64,
    };

    pub inline fn emitTime(self: @This(), opt: EmitTimeOptions) void {
        if (enabled) impl.c.___tracy_emit_gpu_time_serial(.{
            .gpuTime = @bitCast(opt.gpu_time),
            .queryId = opt.query_id,
            .context = self.context,
        });
    }

    pub const CalibrateOptions = struct {
        gpu_time: u64,
        cpu_delta: i64,
    };

    pub inline fn calibrate(self: @This(), opt: CalibrateOptions) void {
        if (enabled) impl.c.___tracy_emit_gpu_calibration_serial(.{
            .gpuTime = @bitCast(opt.gpu_time),
            .cpuDelta = opt.cpu_delta,
            .context = self.context,
        });
    }

    pub inline fn timeSync(self: @This(), gpu_time: u64) void {
        if (enabled) impl.c.___tracy_emit_gpu_time_sync_serial(.{
            .gpuTime = @bitCast(gpu_time),
            .context = self.context,
        });
    }
};

pub const Lock = opaque {
    pub fn init(comptime opt: SourceLocation.InitOptions) *@This() {
        if (enabled) {
            return @ptrCast(impl.c.___tracy_announce_lockable_ctx(@ptrCast(
                SourceLocation.init(opt),
            )));
        }
    }

    pub fn deinit(self: *@This()) void {
        if (enabled) impl.c.___tracy_terminate_lockable_ctx(@ptrCast(self));
    }

    pub fn beforeLock(self: *@This()) bool {
        if (enabled) {
            return impl.c.___tracy_before_lock_lockable_ctx(@ptrCast(self)) != 0;
        } else {
            return true;
        }
    }

    pub fn afterLock(self: *@This()) void {
        if (enabled) impl.c.___tracy_after_lock_lockable_ctx(@ptrCast(self));
    }

    pub fn afterUnlock(self: *@This()) void {
        if (enabled) impl.c.___tracy_after_unlock_lockable_ctx(@ptrCast(self));
    }

    pub fn afterTryUnlock(self: *@This(), acquired: bool) void {
        if (enabled) {
            impl.c.___tracy_after_try_lock_lockable_ctx(@ptrCast(self), @intFromBool(acquired));
        }
    }

    pub fn mark(self: *@This(), loc: *const SourceLocation) void {
        if (enabled) impl.c.___tracy_mark_lockable_ctx(@ptrCast(self), loc);
    }

    pub fn customName(self: *@This(), name: []const u8) void {
        if (enabled) {
            impl.c.___tracy_custom_name_lockable_ctx(@ptrCast(self), name.ptr, name.len);
        }
    }
};

pub const FrameImageOptions = struct {
    image: []const u8,
    width: u16,
    height: u16,
    offset: u8,
    flip: bool,
};

pub inline fn frameImage(opt: FrameImageOptions) void {
    assert(opt.width % 4 == 0);
    assert(opt.height % 4 == 0);
    assert(opt.image.len == opt.width * opt.height * 3);
    assert(opt.width * opt.height * 3 / 6 <= 262144);
    if (enabled) impl.c.___tracy_emit_frame_image(
        opt.image.ptr,
        opt.width,
        opt.height,
        opt.offset,
        @intFromBool(opt.flip),
    );
}

pub fn startupProfiler() void {
    if (enabled) {
        comptime assert(impl.build_options.manual_lifetime);
        impl.c.___tracy_startup_profiler();
    }
}

pub fn shutdownProfiler() void {
    if (enabled) {
        comptime assert(impl.build_options.manual_lifetime);
        impl.c.___tracy_shutdown_profiler();
    }
}

pub const MessageOptions = struct {
    text: []const u8,
    color: ?Color = null,
    callstack_depth: u6 = options.default_callstack_depth,
};

pub fn message(opt: MessageOptions) void {
    assert(opt.callstack_depth <= max_callstack_depth); // Max supported Tracy
    if (enabled) {
        if (opt.color) |color| {
            impl.c.___tracy_emit_messageC(opt.text.ptr, opt.text.len, @bitCast(color), opt.callstack_depth);
        } else {
            impl.c.___tracy_emit_message(opt.text.ptr, opt.text.len, opt.callstack_depth);
        }
    }
}

pub fn appInfo(text: []const u8) void {
    if (enabled) impl.c.___tracy_emit_message_appinfo(text.ptr, text.len);
}

pub const PlotOptions = struct {
    pub const Value = union(enum) {
        f32: f32,
        f64: f64,
        i64: i64,
    };
    name: [*:0]const u8,
    value: Value,
};

pub fn plot(opt: PlotOptions) void {
    if (enabled) {
        switch (opt.value) {
            .f32 => |n| impl.c.___tracy_emit_plot_float(opt.name, n),
            .f64 => |n| impl.c.___tracy_emit_plot(opt.name, n),
            .i64 => |n| impl.c.___tracy_emit_plot_int(opt.name, n),
        }
    }
}

pub const PlotConfigOptions = struct {
    pub const Format = enum(c_int) {
        number,
        memory,
        percentage,
        watt,
    };

    pub const Mode = enum(c_int) {
        line = 0,
        step = 1,
    };

    name: [*:0]const u8,
    format: Format = .number,
    mode: Mode = .line,
    fill: bool = false,
    color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
};

pub fn plotConfig(opt: PlotConfigOptions) void {
    if (enabled) impl.c.___tracy_emit_plot_config(
        opt.name,
        @intFromEnum(opt.format),
        @intFromEnum(opt.mode),
        @intFromBool(opt.fill),
        @bitCast(opt.color),
    );
}

pub const AllocOptions = struct {
    ptr: ?*const anyopaque,
    size: usize,
    secure: bool = false,
    pool_name: ?[*:0]const u8 = null,
    callstack_depth: u6 = options.default_callstack_depth,
};

pub fn alloc(opt: AllocOptions) void {
    assert(opt.callstack_depth <= max_callstack_depth);
    if (enabled) {
        if (opt.pool_name) |pool_name| {
            impl.c.___tracy_emit_memory_alloc_callstack_named(
                opt.ptr,
                opt.size,
                opt.callstack_depth,
                @intFromBool(opt.secure),
                pool_name,
            );
        } else {
            impl.c.___tracy_emit_memory_alloc_callstack(
                opt.ptr,
                opt.size,
                opt.callstack_depth,
                @intFromBool(opt.secure),
            );
        }
    }
}

pub const FreeOptions = struct {
    ptr: ?*const anyopaque,
    pool_name: ?[*:0]const u8 = null,
    secure: bool = false,
    callstack_depth: u6 = options.default_callstack_depth,
};

pub fn free(opt: FreeOptions) void {
    assert(opt.callstack_depth <= max_callstack_depth);
    if (enabled) {
        if (opt.pool_name) |pool_name| {
            impl.c.___tracy_emit_memory_free_callstack_named(
                opt.ptr,
                opt.callstack_depth,
                @intFromBool(opt.secure),
                pool_name,
            );
        } else {
            impl.c.___tracy_emit_memory_free_callstack(
                opt.ptr,
                opt.callstack_depth,
                @intFromBool(opt.secure),
            );
        }
    }
}

pub const Allocator = struct {
    pool_name: ?[*:0]const u8 = null,
    secure: bool = false,
    parent: std.mem.Allocator,

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = @This().alloc,
                .resize = @This().resize,
                .free = @This().free,
                .remap = @This().remap,
            },
        };
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        ra: usize,
    ) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawAlloc(len, alignment, ra);
        if (result) |ptr| {
            tracy_zig.alloc(.{
                .ptr = ptr,
                .size = len,
                .secure = self.secure,
                .pool_name = self.pool_name,
            });
        }
        return result;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ra: usize,
    ) bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawResize(buf, alignment, new_len, ra);
        if (result) {
            tracy_zig.free(.{
                .ptr = buf.ptr,
                .pool_name = self.pool_name,
                .secure = self.secure,
            });
            tracy_zig.alloc(.{
                .ptr = buf.ptr,
                .size = new_len,
                .secure = self.secure,
                .pool_name = self.pool_name,
            });
        }
        return result;
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        ra: usize,
    ) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(buf, alignment, ra);
        tracy_zig.free(.{
            .ptr = buf.ptr,
            .pool_name = self.pool_name,
            .secure = self.secure,
        });
    }

    fn remap(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ra: usize,
    ) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawRemap(buf, alignment, new_len, ra);
        if (result) |remapped| {
            tracy_zig.free(.{
                .ptr = buf.ptr,
                .pool_name = self.pool_name,
                .secure = self.secure,
            });
            tracy_zig.alloc(.{
                .ptr = remapped,
                .size = new_len,
                .secure = self.secure,
                .pool_name = self.pool_name,
            });
        }
        return result;
    }
};

pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8,

    pub const snow: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffafa));
    pub const ghost_white: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff8f8ff));
    pub const white_smoke: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff5f5f5));
    pub const gainsboro: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdcdcdc));
    pub const floral_white: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffaf0));
    pub const old_lace: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffdf5e6));
    pub const linen: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffaf0e6));
    pub const antique_white: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffaebd7));
    pub const papaya_whip: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffefd5));
    pub const blanched_almond: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffebcd));
    pub const bisque: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe4c4));
    pub const peach_puff: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffdab9));
    pub const navajo_white: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffdead));
    pub const moccasin: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe4b5));
    pub const cornsilk: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff8dc));
    pub const ivory: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffff0));
    pub const lemon_chiffon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffacd));
    pub const seashell: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff5ee));
    pub const honeydew: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0fff0));
    pub const mint_cream: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff5fffa));
    pub const azure: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0ffff));
    pub const alice_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0f8ff));
    pub const lavender: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe6e6fa));
    pub const lavender_blush: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff0f5));
    pub const misty_rose: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe4e1));
    pub const white: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffffff));
    pub const black: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff000000));
    pub const dark_slate_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2f4f4f));
    pub const dark_slate_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2f4f4f));
    pub const dim_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff696969));
    pub const dim_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff696969));
    pub const slate_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff708090));
    pub const slate_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff708090));
    pub const light_slate_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff778899));
    pub const light_slate_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff778899));
    pub const gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbebebe));
    pub const grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbebebe));
    pub const x11_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbebebe));
    pub const x11_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbebebe));
    pub const web_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff808080));
    pub const web_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff808080));
    pub const light_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd3d3d3));
    pub const light_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd3d3d3));
    pub const midnight_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff191970));
    pub const navy: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff000080));
    pub const navy_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff000080));
    pub const cornflower_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6495ed));
    pub const dark_slate_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff483d8b));
    pub const slate_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6a5acd));
    pub const medium_slate_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7b68ee));
    pub const light_slate_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8470ff));
    pub const medium_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0000cd));
    pub const royal_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4169e1));
    pub const blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0000ff));
    pub const dodger_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1e90ff));
    pub const deep_sky_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00bfff));
    pub const sky_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff87ceeb));
    pub const light_sky_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff87cefa));
    pub const steel_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4682b4));
    pub const light_steel_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb0c4de));
    pub const light_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffadd8e6));
    pub const powder_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb0e0e6));
    pub const pale_turquoise: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffafeeee));
    pub const dark_turquoise: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ced1));
    pub const medium_turquoise: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff48d1cc));
    pub const turquoise: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff40e0d0));
    pub const cyan: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ffff));
    pub const aqua: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ffff));
    pub const light_cyan: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe0ffff));
    pub const cadet_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5f9ea0));
    pub const medium_aquamarine: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff66cdaa));
    pub const aquamarine: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7fffd4));
    pub const dark_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff006400));
    pub const dark_olive_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff556b2f));
    pub const dark_sea_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8fbc8f));
    pub const sea_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2e8b57));
    pub const medium_sea_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff3cb371));
    pub const light_sea_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff20b2aa));
    pub const pale_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff98fb98));
    pub const spring_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ff7f));
    pub const lawn_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7cfc00));
    pub const green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ff00));
    pub const lime: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ff00));
    pub const x11_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ff00));
    pub const web_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff008000));
    pub const chartreuse: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7fff00));
    pub const medium_spring_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00fa9a));
    pub const green_yellow: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffadff2f));
    pub const lime_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff32cd32));
    pub const yellow_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9acd32));
    pub const forest_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff228b22));
    pub const olive_drab: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6b8e23));
    pub const dark_khaki: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbdb76b));
    pub const khaki: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0e68c));
    pub const pale_goldenrod: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee8aa));
    pub const light_goldenrod_yellow: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffafad2));
    pub const light_yellow: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffffe0));
    pub const yellow: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffff00));
    pub const gold: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffd700));
    pub const light_goldenrod: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeedd82));
    pub const goldenrod: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdaa520));
    pub const dark_goldenrod: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb8860b));
    pub const rosy_brown: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbc8f8f));
    pub const indian_red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd5c5c));
    pub const saddle_brown: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b4513));
    pub const sienna: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa0522d));
    pub const peru: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd853f));
    pub const burlywood: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdeb887));
    pub const beige: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff5f5dc));
    pub const wheat: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff5deb3));
    pub const sandy_brown: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff4a460));
    pub const tan: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd2b48c));
    pub const chocolate: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd2691e));
    pub const firebrick: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb22222));
    pub const brown: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa52a2a));
    pub const dark_salmon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe9967a));
    pub const salmon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffa8072));
    pub const light_salmon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffa07a));
    pub const orange: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffa500));
    pub const dark_orange: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff8c00));
    pub const coral: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff7f50));
    pub const light_coral: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff08080));
    pub const tomato: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff6347));
    pub const orange_red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff4500));
    pub const red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff0000));
    pub const hot_pink: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff69b4));
    pub const deep_pink: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff1493));
    pub const pink: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffc0cb));
    pub const light_pink: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffb6c1));
    pub const pale_violet_red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdb7093));
    pub const maroon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb03060));
    pub const x11_maroon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb03060));
    pub const web_maroon: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff800000));
    pub const medium_violet_red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc71585));
    pub const violet_red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd02090));
    pub const magenta: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff00ff));
    pub const fuchsia: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff00ff));
    pub const violet: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee82ee));
    pub const plum: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdda0dd));
    pub const orchid: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffda70d6));
    pub const medium_orchid: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffba55d3));
    pub const dark_orchid: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9932cc));
    pub const dark_violet: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9400d3));
    pub const blue_violet: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8a2be2));
    pub const purple: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa020f0));
    pub const x11_purple: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa020f0));
    pub const web_purple: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff800080));
    pub const medium_purple: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9370db));
    pub const thistle: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd8bfd8));
    pub const snow1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffafa));
    pub const snow2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee9e9));
    pub const snow3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc9c9));
    pub const snow4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8989));
    pub const seashell1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff5ee));
    pub const seashell2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee5de));
    pub const seashell3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc5bf));
    pub const seashell4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8682));
    pub const antique_white1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffefdb));
    pub const antique_white2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeedfcc));
    pub const antique_white3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc0b0));
    pub const antique_white4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8378));
    pub const bisque1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe4c4));
    pub const bisque2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeed5b7));
    pub const bisque3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdb79e));
    pub const bisque4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7d6b));
    pub const peach_puff1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffdab9));
    pub const peach_puff2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeecbad));
    pub const peach_puff3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdaf95));
    pub const peach_puff4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7765));
    pub const navajo_white1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffdead));
    pub const navajo_white2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeecfa1));
    pub const navajo_white3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdb38b));
    pub const navajo_white4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b795e));
    pub const lemon_chiffon1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffacd));
    pub const lemon_chiffon2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee9bf));
    pub const lemon_chiffon3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc9a5));
    pub const lemon_chiffon4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8970));
    pub const cornsilk1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff8dc));
    pub const cornsilk2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee8cd));
    pub const cornsilk3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc8b1));
    pub const cornsilk4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8878));
    pub const ivory1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffffff0));
    pub const ivory2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeeeee0));
    pub const ivory3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdcdc1));
    pub const ivory4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8b83));
    pub const honeydew1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0fff0));
    pub const honeydew2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe0eee0));
    pub const honeydew3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc1cdc1));
    pub const honeydew4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff838b83));
    pub const lavender_blush1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff0f5));
    pub const lavender_blush2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee0e5));
    pub const lavender_blush3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc1c5));
    pub const lavender_blush4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8386));
    pub const misty_rose1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe4e1));
    pub const misty_rose2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeed5d2));
    pub const misty_rose3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdb7b5));
    pub const misty_rose4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7d7b));
    pub const azure1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0ffff));
    pub const azure2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe0eeee));
    pub const azure3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc1cdcd));
    pub const azure4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff838b8b));
    pub const slate_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff836fff));
    pub const slate_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7a67ee));
    pub const slate_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6959cd));
    pub const slate_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff473c8b));
    pub const royal_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4876ff));
    pub const royal_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff436eee));
    pub const royal_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff3a5fcd));
    pub const royal_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff27408b));
    pub const blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0000ff));
    pub const blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0000ee));
    pub const blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0000cd));
    pub const blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00008b));
    pub const dodger_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1e90ff));
    pub const dodger_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1c86ee));
    pub const dodger_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1874cd));
    pub const dodger_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff104e8b));
    pub const steel_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff63b8ff));
    pub const steel_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5cacee));
    pub const steel_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4f94cd));
    pub const steel_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff36648b));
    pub const deep_sky_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00bfff));
    pub const deep_sky_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00b2ee));
    pub const deep_sky_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff009acd));
    pub const deep_sky_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00688b));
    pub const sky_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff87ceff));
    pub const sky_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7ec0ee));
    pub const sky_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6ca6cd));
    pub const sky_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4a708b));
    pub const light_sky_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb0e2ff));
    pub const light_sky_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa4d3ee));
    pub const light_sky_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8db6cd));
    pub const light_sky_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff607b8b));
    pub const slate_gray1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc6e2ff));
    pub const slate_gray2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb9d3ee));
    pub const slate_gray3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9fb6cd));
    pub const slate_gray4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6c7b8b));
    pub const light_steel_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcae1ff));
    pub const light_steel_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbcd2ee));
    pub const light_steel_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa2b5cd));
    pub const light_steel_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6e7b8b));
    pub const light_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbfefff));
    pub const light_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb2dfee));
    pub const light_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9ac0cd));
    pub const light_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff68838b));
    pub const light_cyan1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe0ffff));
    pub const light_cyan2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd1eeee));
    pub const light_cyan3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb4cdcd));
    pub const light_cyan4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7a8b8b));
    pub const pale_turquoise1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbbffff));
    pub const pale_turquoise2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffaeeeee));
    pub const pale_turquoise3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff96cdcd));
    pub const pale_turquoise4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff668b8b));
    pub const cadet_blue1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff98f5ff));
    pub const cadet_blue2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8ee5ee));
    pub const cadet_blue3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7ac5cd));
    pub const cadet_blue4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff53868b));
    pub const turquoise1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00f5ff));
    pub const turquoise2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00e5ee));
    pub const turquoise3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00c5cd));
    pub const turquoise4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00868b));
    pub const cyan1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ffff));
    pub const cyan2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00eeee));
    pub const cyan3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00cdcd));
    pub const cyan4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff008b8b));
    pub const dark_slate_gray1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff97ffff));
    pub const dark_slate_gray2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8deeee));
    pub const dark_slate_gray3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff79cdcd));
    pub const dark_slate_gray4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff528b8b));
    pub const aquamarine1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7fffd4));
    pub const aquamarine2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff76eec6));
    pub const aquamarine3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff66cdaa));
    pub const aquamarine4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff458b74));
    pub const dark_sea_green1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc1ffc1));
    pub const dark_sea_green2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb4eeb4));
    pub const dark_sea_green3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9bcd9b));
    pub const dark_sea_green4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff698b69));
    pub const sea_green1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff54ff9f));
    pub const sea_green2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4eee94));
    pub const sea_green3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff43cd80));
    pub const sea_green4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2e8b57));
    pub const pale_green1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9aff9a));
    pub const pale_green2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff90ee90));
    pub const pale_green3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7ccd7c));
    pub const pale_green4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff548b54));
    pub const spring_green1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ff7f));
    pub const spring_green2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ee76));
    pub const spring_green3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00cd66));
    pub const spring_green4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff008b45));
    pub const green1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ff00));
    pub const green2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00ee00));
    pub const green3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00cd00));
    pub const green4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff008b00));
    pub const chartreuse1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7fff00));
    pub const chartreuse2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff76ee00));
    pub const chartreuse3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff66cd00));
    pub const chartreuse4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff458b00));
    pub const olive_drab1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc0ff3e));
    pub const olive_drab2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb3ee3a));
    pub const olive_drab3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9acd32));
    pub const olive_drab4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff698b22));
    pub const dark_olive_green1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcaff70));
    pub const dark_olive_green2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbcee68));
    pub const dark_olive_green3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa2cd5a));
    pub const dark_olive_green4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6e8b3d));
    pub const khaki1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffff68f));
    pub const khaki2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeee685));
    pub const khaki3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdc673));
    pub const khaki4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b864e));
    pub const light_goldenrod1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffec8b));
    pub const light_goldenrod2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeedc82));
    pub const light_goldenrod3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdbe70));
    pub const light_goldenrod4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b814c));
    pub const light_yellow1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffffe0));
    pub const light_yellow2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeeeed1));
    pub const light_yellow3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdcdb4));
    pub const light_yellow4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8b7a));
    pub const yellow1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffff00));
    pub const yellow2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeeee00));
    pub const yellow3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdcd00));
    pub const yellow4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b8b00));
    pub const gold1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffd700));
    pub const gold2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeec900));
    pub const gold3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdad00));
    pub const gold4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7500));
    pub const goldenrod1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffc125));
    pub const goldenrod2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeeb422));
    pub const goldenrod3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd9b1d));
    pub const goldenrod4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b6914));
    pub const dark_goldenrod1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffb90f));
    pub const dark_goldenrod2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeead0e));
    pub const dark_goldenrod3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd950c));
    pub const dark_goldenrod4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b6508));
    pub const rosy_brown1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffc1c1));
    pub const rosy_brown2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeeb4b4));
    pub const rosy_brown3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd9b9b));
    pub const rosy_brown4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b6969));
    pub const indian_red1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff6a6a));
    pub const indian_red2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee6363));
    pub const indian_red3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd5555));
    pub const indian_red4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b3a3a));
    pub const sienna1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff8247));
    pub const sienna2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee7942));
    pub const sienna3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd6839));
    pub const sienna4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b4726));
    pub const burlywood1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffd39b));
    pub const burlywood2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeec591));
    pub const burlywood3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdaa7d));
    pub const burlywood4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7355));
    pub const wheat1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe7ba));
    pub const wheat2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeed8ae));
    pub const wheat3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdba96));
    pub const wheat4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7e66));
    pub const tan1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffa54f));
    pub const tan2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee9a49));
    pub const tan3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd853f));
    pub const tan4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b5a2b));
    pub const chocolate1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff7f24));
    pub const chocolate2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee7621));
    pub const chocolate3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd661d));
    pub const chocolate4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b4513));
    pub const firebrick1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff3030));
    pub const firebrick2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee2c2c));
    pub const firebrick3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd2626));
    pub const firebrick4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b1a1a));
    pub const brown1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff4040));
    pub const brown2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee3b3b));
    pub const brown3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd3333));
    pub const brown4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b2323));
    pub const salmon1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff8c69));
    pub const salmon2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee8262));
    pub const salmon3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd7054));
    pub const salmon4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b4c39));
    pub const light_salmon1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffa07a));
    pub const light_salmon2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee9572));
    pub const light_salmon3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd8162));
    pub const light_salmon4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b5742));
    pub const orange1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffa500));
    pub const orange2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee9a00));
    pub const orange3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd8500));
    pub const orange4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b5a00));
    pub const dark_orange1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff7f00));
    pub const dark_orange2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee7600));
    pub const dark_orange3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd6600));
    pub const dark_orange4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b4500));
    pub const coral1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff7256));
    pub const coral2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee6a50));
    pub const coral3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd5b45));
    pub const coral4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b3e2f));
    pub const tomato1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff6347));
    pub const tomato2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee5c42));
    pub const tomato3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd4f39));
    pub const tomato4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b3626));
    pub const orange_red1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff4500));
    pub const orange_red2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee4000));
    pub const orange_red3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd3700));
    pub const orange_red4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b2500));
    pub const red1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff0000));
    pub const red2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee0000));
    pub const red3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd0000));
    pub const red4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b0000));
    pub const deep_pink1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff1493));
    pub const deep_pink2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee1289));
    pub const deep_pink3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd1076));
    pub const deep_pink4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b0a50));
    pub const hot_pink1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff6eb4));
    pub const hot_pink2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee6aa7));
    pub const hot_pink3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd6090));
    pub const hot_pink4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b3a62));
    pub const pink1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffb5c5));
    pub const pink2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeea9b8));
    pub const pink3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd919e));
    pub const pink4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b636c));
    pub const light_pink1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffaeb9));
    pub const light_pink2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeea2ad));
    pub const light_pink3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd8c95));
    pub const light_pink4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b5f65));
    pub const pale_violet_red1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff82ab));
    pub const pale_violet_red2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee799f));
    pub const pale_violet_red3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd6889));
    pub const pale_violet_red4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b475d));
    pub const maroon1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff34b3));
    pub const maroon2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee30a7));
    pub const maroon3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd2990));
    pub const maroon4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b1c62));
    pub const violet_red1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff3e96));
    pub const violet_red2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee3a8c));
    pub const violet_red3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd3278));
    pub const violet_red4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b2252));
    pub const magenta1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff00ff));
    pub const magenta2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee00ee));
    pub const magenta3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd00cd));
    pub const magenta4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b008b));
    pub const orchid1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffff83fa));
    pub const orchid2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffee7ae9));
    pub const orchid3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd69c9));
    pub const orchid4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b4789));
    pub const plum1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffbbff));
    pub const plum2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeeaeee));
    pub const plum3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcd96cd));
    pub const plum4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b668b));
    pub const medium_orchid1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe066ff));
    pub const medium_orchid2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd15fee));
    pub const medium_orchid3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb452cd));
    pub const medium_orchid4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7a378b));
    pub const dark_orchid1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbf3eff));
    pub const dark_orchid2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb23aee));
    pub const dark_orchid3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9a32cd));
    pub const dark_orchid4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff68228b));
    pub const purple1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9b30ff));
    pub const purple2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff912cee));
    pub const purple3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7d26cd));
    pub const purple4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff551a8b));
    pub const medium_purple1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffab82ff));
    pub const medium_purple2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9f79ee));
    pub const medium_purple3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8968cd));
    pub const medium_purple4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5d478b));
    pub const thistle1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffe1ff));
    pub const thistle2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffeed2ee));
    pub const thistle3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcdb5cd));
    pub const thistle4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b7b8b));
    pub const gray0: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff000000));
    pub const grey0: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff000000));
    pub const gray1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff030303));
    pub const grey1: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff030303));
    pub const gray2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff050505));
    pub const grey2: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff050505));
    pub const gray3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff080808));
    pub const grey3: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff080808));
    pub const gray4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0a0a0a));
    pub const grey4: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0a0a0a));
    pub const gray5: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0d0d0d));
    pub const grey5: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0d0d0d));
    pub const gray6: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0f0f0f));
    pub const grey6: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff0f0f0f));
    pub const gray7: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff121212));
    pub const grey7: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff121212));
    pub const gray8: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff141414));
    pub const grey8: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff141414));
    pub const gray9: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff171717));
    pub const grey9: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff171717));
    pub const gray10: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1a1a1a));
    pub const grey10: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1a1a1a));
    pub const gray11: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1c1c1c));
    pub const grey11: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1c1c1c));
    pub const gray12: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1f1f1f));
    pub const grey12: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff1f1f1f));
    pub const gray13: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff212121));
    pub const grey13: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff212121));
    pub const gray14: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff242424));
    pub const grey14: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff242424));
    pub const gray15: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff262626));
    pub const grey15: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff262626));
    pub const gray16: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff292929));
    pub const grey16: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff292929));
    pub const gray17: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2b2b2b));
    pub const grey17: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2b2b2b));
    pub const gray18: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2e2e2e));
    pub const grey18: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff2e2e2e));
    pub const gray19: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff303030));
    pub const grey19: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff303030));
    pub const gray20: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff333333));
    pub const grey20: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff333333));
    pub const gray21: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff363636));
    pub const grey21: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff363636));
    pub const gray22: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff383838));
    pub const grey22: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff383838));
    pub const gray23: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff3b3b3b));
    pub const grey23: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff3b3b3b));
    pub const gray24: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff3d3d3d));
    pub const grey24: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff3d3d3d));
    pub const gray25: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff404040));
    pub const grey25: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff404040));
    pub const gray26: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff424242));
    pub const grey26: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff424242));
    pub const gray27: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff454545));
    pub const grey27: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff454545));
    pub const gray28: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff474747));
    pub const grey28: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff474747));
    pub const gray29: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4a4a4a));
    pub const grey29: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4a4a4a));
    pub const gray30: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4d4d4d));
    pub const grey30: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4d4d4d));
    pub const gray31: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4f4f4f));
    pub const grey31: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4f4f4f));
    pub const gray32: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff525252));
    pub const grey32: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff525252));
    pub const gray33: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff545454));
    pub const grey33: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff545454));
    pub const gray34: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff575757));
    pub const grey34: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff575757));
    pub const gray35: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff595959));
    pub const grey35: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff595959));
    pub const gray36: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5c5c5c));
    pub const grey36: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5c5c5c));
    pub const gray37: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5e5e5e));
    pub const grey37: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff5e5e5e));
    pub const gray38: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff616161));
    pub const grey38: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff616161));
    pub const gray39: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff636363));
    pub const grey39: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff636363));
    pub const gray40: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff666666));
    pub const grey40: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff666666));
    pub const gray41: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff696969));
    pub const grey41: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff696969));
    pub const gray42: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6b6b6b));
    pub const grey42: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6b6b6b));
    pub const gray43: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6e6e6e));
    pub const grey43: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff6e6e6e));
    pub const gray44: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff707070));
    pub const grey44: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff707070));
    pub const gray45: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff737373));
    pub const grey45: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff737373));
    pub const gray46: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff757575));
    pub const grey46: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff757575));
    pub const gray47: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff787878));
    pub const grey47: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff787878));
    pub const gray48: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7a7a7a));
    pub const grey48: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7a7a7a));
    pub const gray49: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7d7d7d));
    pub const grey49: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7d7d7d));
    pub const gray50: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7f7f7f));
    pub const grey50: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff7f7f7f));
    pub const gray51: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff828282));
    pub const grey51: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff828282));
    pub const gray52: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff858585));
    pub const grey52: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff858585));
    pub const gray53: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff878787));
    pub const grey53: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff878787));
    pub const gray54: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8a8a8a));
    pub const grey54: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8a8a8a));
    pub const gray55: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8c8c8c));
    pub const grey55: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8c8c8c));
    pub const gray56: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8f8f8f));
    pub const grey56: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8f8f8f));
    pub const gray57: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff919191));
    pub const grey57: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff919191));
    pub const gray58: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff949494));
    pub const grey58: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff949494));
    pub const gray59: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff969696));
    pub const grey59: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff969696));
    pub const gray60: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff999999));
    pub const grey60: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff999999));
    pub const gray61: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9c9c9c));
    pub const grey61: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9c9c9c));
    pub const gray62: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9e9e9e));
    pub const grey62: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff9e9e9e));
    pub const gray63: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa1a1a1));
    pub const grey63: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa1a1a1));
    pub const gray64: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa3a3a3));
    pub const grey64: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa3a3a3));
    pub const gray65: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa6a6a6));
    pub const grey65: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa6a6a6));
    pub const gray66: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa8a8a8));
    pub const grey66: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa8a8a8));
    pub const gray67: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffababab));
    pub const grey67: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffababab));
    pub const gray68: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffadadad));
    pub const grey68: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffadadad));
    pub const gray69: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb0b0b0));
    pub const grey69: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb0b0b0));
    pub const gray70: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb3b3b3));
    pub const grey70: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb3b3b3));
    pub const gray71: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb5b5b5));
    pub const grey71: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb5b5b5));
    pub const gray72: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb8b8b8));
    pub const grey72: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffb8b8b8));
    pub const gray73: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbababa));
    pub const grey73: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbababa));
    pub const gray74: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbdbdbd));
    pub const grey74: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbdbdbd));
    pub const gray75: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbfbfbf));
    pub const grey75: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffbfbfbf));
    pub const gray76: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc2c2c2));
    pub const grey76: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc2c2c2));
    pub const gray77: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc4c4c4));
    pub const grey77: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc4c4c4));
    pub const gray78: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc7c7c7));
    pub const grey78: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc7c7c7));
    pub const gray79: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc9c9c9));
    pub const grey79: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc9c9c9));
    pub const gray80: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcccccc));
    pub const grey80: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcccccc));
    pub const gray81: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcfcfcf));
    pub const grey81: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffcfcfcf));
    pub const gray82: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd1d1d1));
    pub const grey82: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd1d1d1));
    pub const gray83: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd4d4d4));
    pub const grey83: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd4d4d4));
    pub const gray84: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd6d6d6));
    pub const grey84: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd6d6d6));
    pub const gray85: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd9d9d9));
    pub const grey85: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffd9d9d9));
    pub const gray86: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdbdbdb));
    pub const grey86: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdbdbdb));
    pub const gray87: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdedede));
    pub const grey87: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdedede));
    pub const gray88: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe0e0e0));
    pub const grey88: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe0e0e0));
    pub const gray89: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe3e3e3));
    pub const grey89: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe3e3e3));
    pub const gray90: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe5e5e5));
    pub const grey90: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe5e5e5));
    pub const gray91: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe8e8e8));
    pub const grey91: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffe8e8e8));
    pub const gray92: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffebebeb));
    pub const grey92: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffebebeb));
    pub const gray93: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffededed));
    pub const grey93: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffededed));
    pub const gray94: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0f0f0));
    pub const grey94: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff0f0f0));
    pub const gray95: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff2f2f2));
    pub const grey95: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff2f2f2));
    pub const gray96: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff5f5f5));
    pub const grey96: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff5f5f5));
    pub const gray97: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff7f7f7));
    pub const grey97: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfff7f7f7));
    pub const gray98: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffafafa));
    pub const grey98: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffafafa));
    pub const gray99: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffcfcfc));
    pub const grey99: Color = @bitCast(std.mem.nativeToLittle(u32, 0xfffcfcfc));
    pub const gray100: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffffff));
    pub const grey100: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffffffff));
    pub const dark_grey: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa9a9a9));
    pub const dark_gray: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffa9a9a9));
    pub const dark_blue: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff00008b));
    pub const dark_cyan: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff008b8b));
    pub const dark_magenta: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b008b));
    pub const dark_red: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff8b0000));
    pub const light_green: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff90ee90));
    pub const crimson: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffdc143c));
    pub const indigo: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff4b0082));
    pub const olive: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff808000));
    pub const rebecca_purple: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff663399));
    pub const silver: Color = @bitCast(std.mem.nativeToLittle(u32, 0xffc0c0c0));
    pub const teal: Color = @bitCast(std.mem.nativeToLittle(u32, 0xff008080));
};
