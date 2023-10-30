const std = @import("std");
const world = @import("world.zig");
const app = @import("app.zig");
const context = @import("context.zig");

// Pubic exports
pub const App = app.App;
pub const Entity = world.Entity;
pub const Context = context.Context;

test {
    std.testing.refAllDeclsRecursive(world);
    std.testing.refAllDeclsRecursive(app);
}
