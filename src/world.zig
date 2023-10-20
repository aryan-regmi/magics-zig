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
const ArchetypeStorage = storage.ArchetypeStorage;
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
    archetypes: std.AutoArrayHashMapUnmanaged(ArchetypeHash, ArchetypeStorage),

    /// Maps entities to their metadata/locations/indicies.
    entity_map: std.AutoArrayHashMapUnmanaged(Entity, EntityMetadata),

    /// Creates new `World`.
    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .num_entities = 0,
            .sparse_storages = .{},
            .archetypes = .{},
            .entity_map = .{},
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
        for (self.archetypes.keys()) |archetype_hash| {
            const archetype_storage: *ArchetypeStorage = self.archetypes.getPtr(archetype_hash).?;
            archetype_storage.deinit(self.allocator);
        }
        self.archetypes.deinit(self.allocator);

        // Free entity map
        self.entity_map.deinit(self.allocator);
    }

    /// Adds a new (empty) entity to the world.
    fn spawnEntity(self: *Self) !EntityId {
        const entity_id = self.num_entities;
        self.num_entities += 1;

        // Add empty entry to all sparse storages!
        for (self.sparse_storages.values()) |erased_sparse_storage| {
            try erased_sparse_storage.addEmptyEntry(erased_sparse_storage.ptr, self.allocator);
        }

        //  Add entity data to the entity map (and to the empty archetype storage)
        try self.entity_map.put(self.allocator, Entity{
            .id = entity_id,
        }, EntityMetadata{
            .archetype_hash = EMPTY_ARCHETYPE_HASH,
            .dense_index = 0,
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

    /// Creates a new `ErasedSparseStorage` pointing to a new `SparseStorage(Component)`.
    fn initErasedSparseStorage(self: *Self, comptime Component: type, component: Component, component_hash: ComponentHash, entity: EntityId) !void {
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
                pub fn deinit(ptr: *anyopaque, allocator: Allocator) void {
                    var sparse_storage = ErasedSparseStorage.toSparseStorage(ptr, Component);
                    sparse_storage.deinit(allocator);
                    allocator.destroy(sparse_storage);
                }
            }).deinit,
            .addEmptyEntry = (struct {
                pub fn addEmptyEntry(ptr: *anyopaque, allocator: Allocator) !void {
                    var concrete_storage = ErasedSparseStorage.toSparseStorage(ptr, Component);
                    try concrete_storage.addEmptyEntry(allocator);
                }
            }).addEmptyEntry,
        };

        // Add new `ErasedSparseStorage` to world
        try self.sparse_storages.put(self.allocator, component_hash, erased_storage);
        return;
    }

    /// Creates a new `ErasedDenseStorage` pointing to a new `DenseStorage(Component)`.
    fn initErasedDenseStorage(self: *Self, comptime Component: type, component: Component) !ErasedDenseStorage {
        // Create new `DenseStorage` and add a new entity to it.
        var new_storage: *DenseStorage(Component) = try self.allocator.create(DenseStorage(Component));
        new_storage.* = DenseStorage(Component){
            .total_entites = 0,
            .components = .{},
        };
        new_storage.addNewEntityWithComponentValue(self.allocator, component);

        // Create new `ErasedSparseStorage` from the new `SparseStorage`
        var erased_storage = ErasedDenseStorage{
            .ptr = new_storage,
            .total_entites = 1,
            .deinit = (struct {
                pub fn deinit(ptr: *anyopaque, allocator: Allocator) void {
                    var dense_storage = ErasedDenseStorage.toDenseStorage(ptr, Component);
                    dense_storage.deinit(allocator);
                    allocator.destroy(dense_storage);
                }
            }).deinit,
            .moveEntity = (struct {
                pub fn moveEntity(src: *ErasedDenseStorage, dst: *ErasedDenseStorage, src_idx: usize) !void {
                    // Get concrete dense storages
                    var src_storage = ErasedDenseStorage.toDenseStorage(src.ptr, Component);
                    var dst_storage = ErasedDenseStorage.toDenseStorage(dst.ptr, Component);

                    // Move the component value from `src_storage` to `dst_storage`.
                    const component_val = src_storage.components.orderedRemove(src_idx);
                    try dst_storage.components.append(self.allocator, component_val);

                    // TODO: Update entity map (new dense_index)
                }
            }).moveEntity,
        };

        return erased_storage;
    }

    // FIXME: Implement!
    fn initArchetypeStorage(self: *Self) !void {
        _ = self;

        // TODO: Intialize new dense storages for each component type
        // TODO: Intialize new dense storage for newly added component type
        //
        // TODO: Copy over sparse_storages?
        //
        // TODO: Add new archetype to the world
    }

    /// Adds a component value to the specified entity.
    ///
    /// ## Note
    /// This will create and register a new component storage if one doen't exist.
    fn addComponentToEntity(self: *Self, comptime Component: type, component: Component, entity: EntityId) !void {
        const component_hash: ComponentHash = std.hash_map.hashString(@typeName(Component));

        switch (Component.StorageType) {
            // TODO: Update entity map
            .Sparse => {
                // Add component to pre-existing storage
                if (self.sparse_storages.contains(component_hash)) {
                    const erased_storage: *ErasedSparseStorage = self.sparse_storages.getPtr(component_hash).?;
                    var component_storage = ErasedSparseStorage.toSparseStorage(erased_storage.ptr, Component);

                    // Set the value of the component for the given entity
                    component_storage.setComponentValue(entity, component);
                    return;
                }

                // Initialize component storage if one doesn't exist
                try self.initErasedSparseStorage(Component, component, component_hash, entity);
            },

            .Dense => {
                // Calculate new archetype hash for the entity
                const entity_info: EntityMetadata = self.entity_map.get(Entity{
                    .id = entity,
                }).?;
                const old_hash = entity_info.archetype_hash;
                const new_hash = if (entityHasComponent(entity_info, component_hash))
                    old_hash
                else
                    old_hash ^ component_hash;

                if (self.archetypes.contains(new_hash)) {
                    // Move entity to new,pre-existing archetype
                    if (new_hash != old_hash) {
                        const curr_archetype: *ArchetypeStorage = self.archetypes.getPtr(old_hash).?;
                        const new_archetype: *ArchetypeStorage = self.archetypes.getPtr(new_hash).?;

                        const src_idx = entity_info.dense_index;
                        try curr_archetype.moveEntity(new_archetype, src_idx);
                    }

                    // Just update component value in the same archetype
                    else {
                        const curr_archetype: *ArchetypeStorage = self.archetypes.getPtr(old_hash).?;
                        const erased_dense_storage: *ErasedDenseStorage = curr_archetype.dense_components.getPtr(component_hash).?;
                        var dense_storage = ErasedDenseStorage.toDenseStorage(erased_dense_storage.ptr, Component);
                        dense_storage.components.items[entity_info.dense_index] = component;
                    }

                    return;
                }

                // TODO: Initialize archetype storage if one doesn't exist
                // (Figure out archetype hash)
                try self.initArchetypeStorage();

                // TODO: Set `entity`'s dense index!
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
    {
        const Position = struct {
            const StorageType: storage.StorageType = .Sparse;
            x: u8,
        };
        const component_hash: ComponentHash = std.hash_map.hashString(@typeName(Position));

        const pos = Position{ .x = 10 };
        try world.addComponentToEntity(Position, pos, entity);
        try testing.expectEqual(world.sparse_storages.count(), 1);
        var erased: *ErasedSparseStorage = world.sparse_storages.getPtr(component_hash).?;
        var concrete = ErasedSparseStorage.toSparseStorage(erased.ptr, Position);
        try testing.expectEqual(concrete.components.items[0], Position{ .x = 10 });

        const pos2 = Position{ .x = 90 };
        try world.addComponentToEntity(Position, pos2, entity);
        try testing.expectEqual(world.sparse_storages.count(), 1);
        erased = world.sparse_storages.getPtr(component_hash).?;
        concrete = ErasedSparseStorage.toSparseStorage(erased.ptr, Position);
        try testing.expectEqual(concrete.components.items[0], Position{ .x = 90 });
    }

    // Add `dense` component
    {
        const Velocity = struct {
            const StorageType: storage.StorageType = .Dense;
            x: u8,
        };
        const vel = Velocity{ .x = 10 };
        try world.addComponentToEntity(Velocity, vel, entity);
        // try testing.expectEqual(world.dense_storages.count(), 1);
    }
}
