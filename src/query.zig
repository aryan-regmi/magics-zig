const std = @import("std");
const world_ = @import("world.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const ComponentHash = world_.ComponentHash;
const Entity = world_.Entity;
const EntityInfo = world_.EntityInfo;
const World = world_.World;

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
        entity_loop: for (self._world._entity_map.keys()) |entity| {
            var is_valid: usize = 0;

            // Loop through all associated components of the entity to check if the entity has all of them
            const entity_info: *EntityInfo = self._world._entity_map.getPtr(entity).?;
            const associated_components = entity_info.getAssociatedComponents();
            for (associated_components.items) |associated_component| {
                for (self._queried_hashes.items) |queried_component| {
                    // Increment if a match is found
                    if (associated_component == queried_component) {
                        is_valid += 1;
                    }

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
