const std = @import("std");
const world = @import("world.zig");
const storage = @import("storage.zig");
const scheduler = @import("scheduler.zig");
const context = @import("context.zig");
const Allocator = std.mem.Allocator;
const HashMap = std.AutoArrayHashMapUnmanaged;
const Context = context.Context;
const System = scheduler.System;
const Scheduler = scheduler.Scheduler;
const SchedulerType = scheduler.SchedulerType;
const World = world.World;
const Entity = world.Entity;
const ComponentHash = world.ComponentHash;
const ErasedSparseStorage = storage.ErasedSparseStorage;

// TODO: Add dense/arcehtype storage

const AppOpts = struct {
    scheduler_type: SchedulerType = .SingleThreaded,
};

/// The main ECS app.
const App = struct {
    const Self = @This();

    /// The allocator used for internal allocations.
    allocator: Allocator,

    /// The world containing all entities and components for the ECS.
    world: World,

    /// Storages for sparse component types.
    sparse_component_storages: HashMap(ComponentHash, ErasedSparseStorage) = .{},

    /// The scheduler that runs the ECS's systems.
    scheduler: Scheduler,

    /// Initialize a new ECS app.
    pub fn init(allocator: Allocator, opts: AppOpts) Self {
        return .{
            .allocator = allocator,
            .world = World.init(),
            .scheduler = Scheduler{ .type = opts.scheduler_type },
        };
    }

    /// Frees all the memory used by the ECS.
    pub fn deinit(self: *Self) void {
        // Deinit the sparse storages
        self.sparse_component_storages.deinit(self.allocator);
        // Deinit the scheduler
        self.scheduler.deinit(self.allocator);
    }

    /// Runs the systems added to the ECS.
    pub fn run(self: *Self) !void {
        try self.scheduler.run();
    }

    // TODO: Add stages to run ordered systems
    pub fn addSystem(self: *Self, system: System) !void {
        try self.scheduler.addSystem(self.allocator, system);
    }
};

test "Can initialize new app" {
    const testing = std.testing;
    const ALLOC = testing.allocator;

    var app = App.init(ALLOC, .{});
    defer app.deinit();
    try testing.expectEqual(app.world.total_entities, 0);
}

test "Can run app" {
    const testing = std.testing;
    const ALLOC = testing.allocator;

    var app = App.init(ALLOC, .{});
    defer app.deinit();

    try app.run();
}

test "Can run systems" {
    const testing = std.testing;
    const ALLOC = testing.allocator;

    const SYSTEMS = struct {
        pub fn system1(ctx: Context) !void {
            _ = ctx;
            std.debug.print("Sys1\n", .{});
        }

        pub fn system2(ctx: Context) !void {
            _ = ctx;
            std.debug.print("Sys2\n", .{});
        }
    };

    var app = App.init(ALLOC, .{});
    defer app.deinit();

    try app.addSystem(SYSTEMS.system1);
    try app.addSystem(SYSTEMS.system2);
    try app.run();
}
