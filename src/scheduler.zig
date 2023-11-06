const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const context = @import("context.zig");

/// The type of a scheduler (single or multi-threaded).
pub const SchedulerType = enum {
    SingleThreaded,
    MultiThreaded,
};

/// Options for adding a system.
pub const SystemOpts = struct {
    /// Possible update types for a system.
    pub const UpdateType = enum {
        /// Run only once at initialization.
        Setup,

        /// Run as much as possible per frame.
        Update,

        /// Run at a fixed (specified) rate.
        FixedUpdate,
    };

    /// The update type of the system.
    ///
    /// Defaults to `Update`.
    update_type: UpdateType = .Update,

    /// FPS for `FixedUpdate`.
    ///
    /// Defaults to 60 fps.
    fixed_update_rate: usize = 60,

    /// Name of the system (used for ordering).
    name: []const u8,
};

// TODO: Make this multi-threaded!
// TODO: Add stages to run ordered systems
//
/// The scheduler used to run systems in the ECS.
pub const Scheduler = struct {
    const Self = @This();

    /// The type of the scheduler to use.
    type: SchedulerType = .SingleThreaded,

    /// The systems to run in the ECS.
    systems: ArrayList(System) = .{},

    /// Frees all the memory used by the scheduler.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.systems.deinit(allocator);
    }

    /// Adds a system to the scheduler.
    pub fn addSystem(self: *Self, allocator: Allocator, system: System, opts: SystemOpts) !void {
        _ = opts;
        if (self.type == .SingleThreaded) {
            try self.systems.append(allocator, system);
        }

        // TODO: Add multi-threaded logic
    }

    /// Runs the systems in the scheduler.
    pub fn run(self: *Self, ctx: *context.Context) !void {
        if (self.type == .SingleThreaded) {
            for (self.systems.items) |system| {
                try system(ctx);
            }
        }

        // TODO: Run systems in multi-threaded queues?
    }
};

/// A function that can be run by the ECS.
pub const System = *const fn (ctx: *context.Context) anyerror!void;
