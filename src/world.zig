const std = @import("std");
const storage = @import("storage.zig");
const entity_ = @import("entity.zig");
const Allocator = std.mem.Allocator;
const Entity = entity_.Entity;
const EntityId = entity_.EntityId;
const EntityMetadata = entity_.EntityMetadata;
const ErasedSparseStorage = storage.ErasedSparseStorage;
const SparseStorage = storage.SparseStorage;
const ErasedDenseStorage = storage.ErasedDenseStorage;
const DenseStorage = storage.DenseStorage;
const ComponentHash = storage.ComponentHash;
const ArchetypeHash = storage.ArchetypeHash;
const EMPTY_ARCHETYPE_HASH = storage.EMPTY_ARCHETYPE_HASH;

// NOTE: Component must have a `const StorageType: storage.StorageType` member
//
// struct {
//    const StorageType: storage.StorageType = .Sparse;
// };
//

/// The underyling world that contains all entities, components, and resources
/// for the ECS.
const World = struct {
    const Self = @This();

    /// Used for internal allocations in the ECS.
    allocator: Allocator,

    /// Total number of entities in the world.
    num_entities: usize,

    /// Storages for sparse component types.
    sparse_storages: std.AutoArrayHashMapUnmanaged(ComponentHash, ErasedSparseStorage),

    /// Storages for dense component types (archetypes).
    dense_storages: std.AutoArrayHashMapUnmanaged(ArchetypeHash, ErasedDenseStorage),

    /// Maps entities to their metadata/locations/indicies.
    entity_map: std.AutoArrayHashMapUnmanaged(Entity, EntityMetadata),

    /// Current generation of entities.
    ///
    /// ## Note
    /// This gets "bumped" everytime an entity is removed from the `World`.
    current_generation: usize,

    /// Creates new `World`.
    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .num_entities = 0,
            .sparse_storages = .{},
            .dense_storages = .{},
            .entity_map = .{},
            .current_generation = 0,
        };
    }

    /// Frees up memory used by `World`.
    fn deinit(self: *Self) void {
        self.num_entities = 0;

        // Remove all sparse storages
        for (self.sparse_storages.values()) |erased_storage| {
            erased_storage.deinit(erased_storage.ptr, self.allocator);
        }
        self.sparse_storages.deinit(self.allocator);

        // Remove all dense storages
        for (self.dense_storages.values()) |erased_storage| {
            erased_storage.deinit(erased_storage.ptr, self.allocator);
        }
        self.dense_storages.deinit(self.allocator);

        // Free entity map
        self.entity_map.deinit(self.allocator);
    }

    /// Adds a new (empty) entity to the world.
    fn spawnEntity(self: *Self) !EntityId {
        const entity_id = self.num_entities;
        self.num_entities += 1;

        //  Add entity data to the entity map
        try self.entity_map.put(self.allocator, Entity{
            .id = entity_id,
            .generation = self.current_generation,
        }, EntityMetadata{
            .archetype_hash = EMPTY_ARCHETYPE_HASH,
            .dense_location = 0,
            .component_types = .{},
        });

        return entity_id;
    }

    /// Checks if the entity described by `entity_info` has a component with the specified hash.
    fn entityHasComponent(entity_info: EntityMetadata, component_hash: ComponentHash) bool {
        for (entity_info.component_types.items) |hash| {
            if (hash == component_hash) {
                return true;
            }
        }
        return false;
    }

    /// Adds a component value to the specified entity.
    ///
    /// ## Note
    /// This will create and register a new component storage if one doen't exist.
    fn addComponentToEntity(self: *Self, comptime Component: type, component: Component, entity: EntityId) !void {
        const component_hash: ComponentHash = std.hash_map.hashString(@typeName(Component));

        switch (Component.StorageType) {
            .Sparse => {
                // Add component to pre-existing storage
                if (self.sparse_storages.contains(component_hash)) {
                    const erased_storage: *ErasedSparseStorage = self.sparse_storages.getPtr(component_hash).?;
                    var component_storage = ErasedSparseStorage.toSparseStorage(erased_storage.ptr, Component);

                    // Add new entry to storage if a new entity has been added to the world
                    if (component_storage.total_entites < self.num_entities) {
                        const new_entries = self.num_entities - component_storage.total_entites;
                        for (0..new_entries) |_| {
                            try component_storage.addEmptyEntry(self.allocator);
                        }
                    }

                    // Set the value of the component for the given entity
                    component_storage.setComponentValue(entity, component);
                    return;
                }

                // Initialize component storage if one doesn't exist
                {
                    // Create new `SparseStorage` w/ `num_entities` entries
                    var new_storage: *SparseStorage(Component) = try self.allocator.create(SparseStorage(Component));
                    new_storage.* = SparseStorage(Component){
                        .total_entites = 0,
                        .components = .{},
                    };
                    for (0..self.num_entities) |_| {
                        try new_storage.addEmptyEntry(self.allocator);
                    }
                    new_storage.setComponentValue(entity, component);

                    // Create new `ErasedSparseStorage` from the new `SparseStorage`
                    var erased_storage = ErasedSparseStorage{
                        .ptr = new_storage,
                        .deinit = (struct {
                            pub fn deinit(erased: *anyopaque, allocator: Allocator) void {
                                var ptr = ErasedSparseStorage.toSparseStorage(erased, Component);
                                ptr.deinit(allocator);
                                allocator.destroy(ptr);
                            }
                        }).deinit,
                    };

                    // Add new `ErasedSparseStorage` to world
                    try self.sparse_storages.put(self.allocator, component_hash, erased_storage);
                    return;
                }
            },

            .Dense => {
                // Calculate new archetype hash for the entity
                const entity_info: EntityMetadata = self.entity_map.get(Entity{
                    .id = entity,
                    .generation = self.current_generation,
                }).?;
                const old_hash = entity_info.archetype_hash;
                const new_hash = if (entityHasComponent(entity_info, component_hash))
                    old_hash
                else
                    old_hash ^ component_hash;

                // Add component to pre-existing storage
                if (self.dense_storages.contains(new_hash)) {
                    if (new_hash != old_hash) {
                        // TODO: Move entity to other archetype
                        //
                        // TODO: Get source and dest indicies
                    }
                }

                // TODO: Initialize component storage if one doesn't exist
            },
        }
    }
};

test "Can create new world" {
    const testing = std.testing;
    const TAlloc = testing.allocator;

    var world = World.init(TAlloc);
    defer world.deinit();

    try testing.expectEqual(world.allocator, TAlloc);
    try testing.expectEqual(world.num_entities, 0);
    try testing.expectEqual(world.sparse_storages.count(), 0);
}

test "Can spawn new entity" {
    const testing = std.testing;
    const TAlloc = testing.allocator;

    var world = World.init(TAlloc);
    defer world.deinit();

    const entity = try world.spawnEntity();
    try testing.expectEqual(entity, 0);
    try testing.expectEqual(world.num_entities, 1);
}

test "Can add component to entity" {
    const testing = std.testing;
    const TAlloc = testing.allocator;

    var world = World.init(TAlloc);
    defer world.deinit();
    const entity = try world.spawnEntity();

    // Add `sparse` component
    const Position = struct {
        const StorageType: storage.StorageType = .Sparse;
        x: u8,
    };
    const pos = Position{ .x = 10 };
    try world.addComponentToEntity(Position, pos, entity);
    try testing.expectEqual(world.sparse_storages.count(), 1);

    // Add `dense` component
    const Velocity = struct {
        const StorageType: storage.StorageType = .Dense;
        x: u8,
    };
    const vel = Velocity{ .x = 10 };
    try world.addComponentToEntity(Velocity, vel, entity);
    try testing.expectEqual(world.dense_storages.count(), 1);
}
