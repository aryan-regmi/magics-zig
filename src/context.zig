const std = @import("std");
const world_ = @import("world.zig");
const storage = @import("storage.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const ComponentHash = world_.ComponentHash;
const Entity = world_.Entity;
const World = world_.World;
const ErasedSparseStorage = storage.ErasedSparseStorage;

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

    // TODO: Add `queryMut` function
};

// TODO: Move to separate file
pub const Query = struct {
    const Self = @This();

    /// The allocator used for internal allocations.
    _allocator: Allocator,

    /// The underlying ECS world.
    _world: *World,

    /// Hashes of the component types being queried.
    _queried_hashes: ArrayList(ComponentHash) = .{},

    /// Free the memory used by the query.
    pub fn deinit(self: *Self) void {
        self._queried_hashes.deinit(self._allocator);
    }

    /// A response from a query.
    pub const QueryRes = struct {
        _entity: Entity,
        _component_values: HashMap(ComponentHash, *anyopaque),
    };

    /// An iterator over a query.
    pub const Iterator = struct {
        _allocator: Allocator,

        _entities: ArrayList(Entity),

        // _sparse_storages: HashMap(ComponentHash, *ErasedSparseStorage),

        _num_entities: usize,
        _curr_idx: usize = 0,

        fn init(allocator: Allocator, entities: ArrayList(Entity)) Iterator {
            return .{
                ._allocator = allocator,
                ._entities = entities,
                ._num_entities = entities.items.len,
            };
        }

        pub fn deinit(self: *Iterator) void {
            self._entities.deinit(self._allocator);
            // self._sparse_storages.deinit(self._allocator);
        }

        /// Gets the next value in the iterator.
        pub fn next(self: *Iterator) ?Entity {
            if (self._curr_idx < self._num_entities) {
                var idx = self._curr_idx;
                self._curr_idx += 1;
                return self._entities.items[idx];
            }

            return null;
        }
    };

    // TODO: Free storages before returning null!
    pub fn iterator(self: *Self) ?Iterator {
        // var sparse_storages: HashMap(ComponentHash, *ErasedSparseStorage) = .{};
        var entities: ArrayList(Entity) = .{};

        // Check entity map to get list of valid entities
        const num_component_types = self._queried_hashes.items.len;
        // std.debug.print("\nKeys: {any}\n", .{self._world._entity_map.keys()});
        // std.debug.print("\nValues: {any}\n", .{self._world._entity_map.values()});
        // std.debug.print("QTypesN: {any}\n", .{num_component_types});
        entity_loop: for (self._world._entity_map.keys()) |entity| {
            std.debug.print("\net {}\n", .{entity});

            var is_valid: usize = 0;

            // Loop through all associated components of the entity to check if the entity has all of them
            var associated_components: *ArrayList(ComponentHash) = self._world._entity_map.getPtr(entity).?;
            std.debug.print("ATypesN: {any}\n", .{associated_components.items.len});
            std.debug.print("ATypes: {any}\n", .{associated_components.items});
            std.debug.print("QTypes: {any}\n", .{self._queried_hashes.items});
            for (associated_components.items) |associated_component| {
                for (self._queried_hashes.items) |queried_component| {
                    // Increment if a match is found
                    if (associated_component == queried_component) {
                        is_valid += 1;
                    }

                    std.debug.print("Associated Type: {}\n", .{associated_component});
                    std.debug.print("Queried Type: {}\n", .{queried_component});

                    // Add to `entities` list if it's valid
                    if (is_valid == num_component_types) {
                        entities.append(self._allocator, entity) catch return null;
                        continue :entity_loop;
                    }
                }
            }
        }

        var iter = Iterator.init(self._allocator, entities);

        // TODO: Add logic for dense storages

        return iter;
    }
};
