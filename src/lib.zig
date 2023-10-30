const std = @import("std");
const world = @import("world.zig");
const app = @import("app.zig");

test {
    std.testing.refAllDeclsRecursive(world);
    std.testing.refAllDeclsRecursive(app);
}
