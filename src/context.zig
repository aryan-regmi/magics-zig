const std = @import("std");
const world_ = @import("world.zig");
const Entity = world_.Entity;
const World = world_.World;

/// The context used to interact with the ECS.
pub const Context = struct {
    const Self = @This();

    _world: *World,

    /// Initializes a new context.
    ///
    /// ## Note
    /// This is only for internal use.
    pub fn _init(world: *World) Self {
        return .{
            ._world = world,
        };
    }

    /// Spawns an new/empty entity into the world.
    pub fn spawn(self: *Self) !Entity {
        return self._world.spawn();
    }

    /// Despawns an entity from the world.
    pub fn despawn(self: *Self, entity: Entity) !void {
        return self._world.despawn(entity);
    }

    /// Adds the given component to the entity.
    pub fn addComponent(self: *Self, entity: Entity, component: anytype) !void {
        return try self._world.addComponentToEntity(entity, component);
    }

    pub fn totalNumEntities(self: *Self) usize {
        return self._world.getTotalEntities();
    }
};
