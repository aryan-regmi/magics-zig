const std = @import("std");
const storage = @import("storage.zig");
const Allocator = std.mem.Allocator;
const ErasedSparseStorage = storage.ErasedSparseStorage;
const SparseStorage = storage.SparseStorage;
const ErasedDenseStorage = storage.ErasedDenseStorage;
const DenseStorage = storage.DenseStorage;
const ComponentHash = storage.ComponentHash;
const ArchetypeHash = storage.ArchetypeHash;

/// Represents an entity in the ECS.
const Entity = usize;

// const EntityMetadata = struct {
//     generation: usize = 0,
//     index: usize,
// };

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

    allocator: Allocator,

    num_entities: usize,

    sparse_storages: std.AutoArrayHashMapUnmanaged(ComponentHash, ErasedSparseStorage),

    dense_storages: std.AutoArrayHashMapUnmanaged(ArchetypeHash, ErasedDenseStorage),

    /// Creates new `World`.
    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .num_entities = 0,
            .sparse_storages = .{},
            .dense_storages = .{},
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
    }

    /// Adds a new (empty) entity to the world.
    fn spawnEntity(self: *Self) Entity {
        const entity = self.num_entities;
        self.num_entities += 1;
        return entity;
    }

    /// Adds a component value to the specified entity.
    ///
    /// ## Note
    /// This will create and register a new component storage if one doen't exist.
    fn addComponentToEntity(self: *Self, comptime Component: type, component: Component, entity: Entity) !void {
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
                // TODO: Calculate new archetype hash for the entity

                // TODO: Add component to pre-existing storage
                //  - Move from old archetype if necessary
                if (self.dense_storages.contains(component_hash)) {}

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

    const entity = world.spawnEntity();
    try testing.expectEqual(entity, 0);
    try testing.expectEqual(world.num_entities, 1);
}

test "Can add component to entity" {
    const testing = std.testing;
    const TAlloc = testing.allocator;

    var world = World.init(TAlloc);
    defer world.deinit();

    const entity = world.spawnEntity();
    const Position = struct {
        const StorageType: storage.StorageType = .Sparse;
        x: u8,
    };
    const pos = Position{ .x = 10 };
    try world.addComponentToEntity(Position, pos, entity);

    try testing.expectEqual(world.sparse_storages.count(), 1);
}
