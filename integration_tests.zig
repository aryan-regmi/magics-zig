const std = @import("std");
const testing = std.testing;
const magics = @import("src/lib.zig");
const App = magics.App;
const Entity = magics.Entity;
const Context = magics.Context;

const ALLOC = std.testing.allocator;

const TestComponent = struct {
    pub const StorageType: magics.StorageType = .Sparse;
    val: i32,
};

const TestComponent2 = struct {
    pub const StorageType: magics.StorageType = .Sparse;
    name: []const u8,
};

fn spawnEntitySystem(ctx: *Context) !void {
    const entity = try ctx.spawn();
    try testing.expectEqual(entity, 0);
    try ctx.addComponent(entity, TestComponent{ .val = 42 });
    try ctx.addComponent(entity, TestComponent2{ .name = "Entity1" });
    try testing.expectEqual(ctx.totalNumEntities(), 1);

    const entity2 = try ctx.spawn();
    try testing.expectEqual(entity2, 1);
    try ctx.addComponent(entity2, TestComponent{ .val = 99 });
    try ctx.addComponent(entity2, TestComponent2{ .name = "Entity2" });
    try testing.expectEqual(ctx.totalNumEntities(), 2);
}

fn despawnEntitySystem(ctx: *Context) !void {
    try testing.expectEqual(ctx.totalNumEntities(), 2);

    try ctx.despawn(0);
    try testing.expectEqual(ctx.totalNumEntities(), 1);
}

fn respawnEntitySystem(ctx: *Context) !void {
    const entity = try ctx.spawn();
    try testing.expectEqual(entity, 0);
    try ctx.addComponent(entity, TestComponent{ .val = 40 });
    try testing.expectEqual(ctx.totalNumEntities(), 2);

    const entity3 = try ctx.spawn();
    try testing.expectEqual(entity3, 2);
    try ctx.addComponent(entity, TestComponent{ .val = 40 });
    try testing.expectEqual(ctx.totalNumEntities(), 3);
}

fn queryEntitySystem(ctx: *Context) !void {
    var component_query = try ctx.query(&[_]type{ TestComponent, TestComponent2 });
    defer component_query.deinit();

    var iter = component_query.iterator().?;
    defer iter.deinit();
    while (iter.next()) |entity| {
        var component_val = ctx.getComponent(TestComponent, entity).?;
        if (entity == 0) {
            try testing.expectEqual(component_val.val, 42);
        } else if (entity == 1) {
            try testing.expectEqual(component_val.val, 99);
        }
    }
}

test "Can spawn/despawn entities" {
    var app = App.init(ALLOC, .{});
    defer app.deinit();

    try app.addSystem(spawnEntitySystem);
    try app.addSystem(despawnEntitySystem);
    try app.addSystem(respawnEntitySystem);

    try app.run();
}

test "Can query entities" {
    var app = App.init(ALLOC, .{});
    defer app.deinit();

    try app.addSystem(spawnEntitySystem);
    try app.addSystem(queryEntitySystem);
    try app.run();
}
