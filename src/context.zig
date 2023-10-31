const std = @import("std");
const world_ = @import("world.zig");
const storage = @import("storage.zig");
const query = @import("query.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const ComponentHash = world_.ComponentHash;
const Entity = world_.Entity;
const World = world_.World;
const ErasedSparseStorage = storage.ErasedSparseStorage;
const Query = query.Query;

/// The context used to interact with the ECS.
pub const Context = struct {
    const Self = @This();

    /// The underlying ECS world.
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

    /// Gets the total number of entities in the world.
    pub fn totalNumEntities(self: *Self) usize {
        return self._world.getTotalEntities();
    }

    /// Spawns an new/empty entity into the world.
    pub fn spawn(self: *Self) !Entity {
        return try self._world.spawn();
    }

    /// Despawns an entity from the world.
    pub fn despawn(self: *Self, entity: Entity) !void {
        return self._world.despawn(entity);
    }

    /// Adds the given component to the entity.
    pub fn addComponent(self: *Self, entity: Entity, component: anytype) !void {
        return try self._world.addComponentToEntity(entity, component);
    }

    /// Queries the world for entites with the given components.
    pub fn query(self: *Self, comptime component_types: []const type) !Query {
        var query_ = Query{ ._allocator = self._world._allocator, ._world = self._world };
        inline for (component_types) |t| {
            const component_hash = std.hash_map.hashString(@typeName(t));
            try query_._queried_hashes.append(self._world._allocator, component_hash);
        }

        return query_;
    }

    /// Gets the component value for the specifed entity.
    pub fn getComponent(self: *Self, comptime Component: type, entity: Entity) ?Component {
        return self._world.getComponentForEntity(Component, entity);
    }
};
