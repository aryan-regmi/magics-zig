const std = @import("std");
const world = @import("world.zig");
const app = @import("app.zig");

// TODO: Make all private funcs and members underscored! (and not use it outside its file)

test {
    std.testing.refAllDeclsRecursive(world);
    std.testing.refAllDeclsRecursive(app);
}
