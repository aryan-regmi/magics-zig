const std = @import("std");
const storage = @import("storage.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Hashmap = std.AutoArrayHashMapUnmanaged;
const ErasedSparseStorage = storage.ErasedSparseStorage;
const SparseStorage = storage.SparseComponentStorage;

// NOTE: All `Component` types must have a `storage::StorageType` defined to be
// either `.Sparse` or `.Dense`.

/// Represents an entity in the world.
pub const Entity = usize;

/// The hash of a component type.
pub const ComponentHash = u64;

/// The world that contains all entities and their components in the ECS.
pub const World = struct {
    const Self = @This();

    /// The allocator used for internal allocations.
    _allocator: Allocator,

    /// The total number of entities in the world.
    _total_entities: usize = 0,

    /// Sparse component storages.
    _sparse_components: Hashmap(ComponentHash, ErasedSparseStorage) = .{},

    /// List of entities removed from the world.
    _removed_entities: ArrayList(Entity) = .{},

    /// Map of entities to their associated component types.
    _entity_map: Hashmap(Entity, ArrayList(ComponentHash)) = .{},

    /// Creates new `World`.
    pub fn init(allocator: Allocator) Self {
        return Self{ ._allocator = allocator };
    }

    /// Destroys the world and frees any allocations it made.
    pub fn deinit(self: *Self) void {
        // Free all sparse components
        for (self._sparse_components.keys()) |component_type| {
            var erased_storage: *ErasedSparseStorage = self._sparse_components.getPtr(component_type).?;
            erased_storage.deinit(self._allocator);
        }
        self._sparse_components.deinit(self._allocator);

        // Free removed entities list
        self._removed_entities.deinit(self._allocator);

        // Free entity map
        for (self._entity_map.keys()) |entity| {
            self._entity_map.getPtr(entity).?.deinit(self._allocator);
        }
        self._entity_map.deinit(self._allocator);
    }

    /// Returns the total number of entities in the world.
    pub fn getTotalEntities(self: *Self) usize {
        return self._total_entities;
    }

    /// Spawns an empty entity.
    pub fn spawn(self: *Self) !Entity {
        var entity: Entity = undefined;

        if (self._removed_entities.items.len == 0) {
            entity = self._total_entities;
            // Add empty entry to all sparse component storages
            for (self._sparse_components.keys()) |component_type| {
                var erased_storage: *ErasedSparseStorage = self._sparse_components.getPtr(component_type).?;
                try erased_storage.addEmptyEntity(self._allocator);
            }
        } else {
            // Grab entity from removed list
            entity = self._removed_entities.pop();
        }

        // Add empty entry to entity map
        var associated_components = try ArrayList(ComponentHash).initCapacity(self._allocator, 1);
        try self._entity_map.put(self._allocator, entity, associated_components);

        self._total_entities += 1;
        return entity;
    }

    /// Despawns an entity.
    pub fn despawn(self: *Self, entity: Entity) !void {
        // Remove component values for all existing components
        for (self._sparse_components.keys()) |component_type| {
            var erased_storage: *ErasedSparseStorage = self._sparse_components.getPtr(component_type).?;
            _ = erased_storage.removeEntityErased(entity);
        }

        // TODO: Remove component data from dense storages

        self._total_entities -= 1;
        try self._removed_entities.append(self._allocator, entity);

        // Update entity map
        var associated_components = self._entity_map.getPtr(entity).?;
        associated_components.deinit(self._allocator);
        _ = self._entity_map.swapRemove(entity);
    }

    /// Adds the specified component to the entity.
    pub fn addComponentToEntity(self: *Self, entity: Entity, component: anytype) !void {
        const ComponentType = @TypeOf(component);
        const COMPONENT_HASH = std.hash_map.hashString(@typeName(ComponentType));

        comptime {
            if (!@hasDecl(ComponentType, "StorageType")) {
                @compileError("The component type must have a `pub const StorageType: storage.StorageType` field");
            }
        }

        if (ComponentType.StorageType == storage.StorageType.Sparse) {
            // If component type exists already, then just update the existing value
            if (self._sparse_components.contains(COMPONENT_HASH)) {
                // Update the component value
                var erased_storage: *ErasedSparseStorage = self._sparse_components.getPtr(COMPONENT_HASH).?;
                erased_storage.updateValue(ComponentType, entity, component);
                return;
            }

            // Create new component type storage
            var new_storage = try ErasedSparseStorage.init(ComponentType, self._allocator, self._total_entities);
            new_storage.updateValue(ComponentType, entity, component);
            try self._sparse_components.put(self._allocator, COMPONENT_HASH, new_storage);

            // Update entity map
            var associated_components: *ArrayList(ComponentHash) = self._entity_map.getPtr(entity).?;
            try associated_components.append(self._allocator, COMPONENT_HASH);
        }

        // TODO: Add logic for dense/archetype storage
    }

    /// Removes the specified component type from the entity.
    pub fn removeComponentFromEntity(self: *Self, comptime Component: type, entity: Entity) ?Component {
        const COMPONENT_HASH = std.hash_map.hashString(@typeName(Component));

        if (Component.StorageType == .Sparse) {
            // Remove component if it exists for the specified component
            if (self._sparse_components.contains(COMPONENT_HASH)) {
                var existing_storage: *ErasedSparseStorage = self._sparse_components.getPtr(COMPONENT_HASH).?;
                return existing_storage.removeEntity(Component, entity);
            }

            return null;
        }

        // TODO: Add `Dense` logic

        // Update entity map
        var associated_components: ArrayList(ComponentHash) = self._entity_map.getPtr(entity).?;
        for (associated_components.items, 0..) |component_hash, i| {
            if (component_hash == COMPONENT_HASH) {
                associated_components.swapRemove(i);
                break;
            }
        }
    }

    /// Gets the component value (of the specified type) for the entity.
    pub fn getComponentForEntity(self: *Self, comptime Component: type, entity: Entity) ?Component {
        if (Component.StorageType == .Sparse) {
            const COMPONENT_HASH = std.hash_map.hashString(@typeName(Component));

            var erased_storage: *ErasedSparseStorage = self._sparse_components.getPtr(COMPONENT_HASH).?;
            var concrete = erased_storage.toConcrete(Component);
            return concrete._data.items[entity];
        }

        // TODO: Handle `Dense` storage
    }

    // TODO: Add `removeComponentStorage` function? (should be called if no entities are stored in it)
};

test "Can create world" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var world = World.init(allocator);
    defer world.deinit();
}

test "Can spawn empty entity" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var world = World.init(allocator);
    defer world.deinit();

    const e0 = try world.spawn();
    try testing.expectEqual(e0, 0);

    const e1 = try world.spawn();
    try testing.expectEqual(e1, 1);
}

test "Can add component to entity" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestStruct = struct {
        const StorageType: storage.StorageType = .Sparse;
        val: i32,
    };

    var world = World.init(allocator);
    defer world.deinit();

    var entity = try world.spawn();
    try world.addComponentToEntity(entity, TestStruct{ .val = 42 });
}

test "Can get component for entity" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestStruct = struct {
        const StorageType: storage.StorageType = .Sparse;
        val: i32,
    };

    var world = World.init(allocator);
    defer world.deinit();

    var entity = try world.spawn();
    try world.addComponentToEntity(entity, TestStruct{ .val = 42 });

    var test_struct: TestStruct = world.getComponentForEntity(TestStruct, entity).?;
    try testing.expectEqual(test_struct.val, 42);

    try world.addComponentToEntity(entity, TestStruct{ .val = 99 });
    test_struct = world.getComponentForEntity(TestStruct, entity).?;
    try testing.expectEqual(test_struct.val, 99);
}

test "Can remove component from entity" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestStruct = struct {
        const StorageType: storage.StorageType = .Sparse;
        val: i32,
    };

    const TestStruct2 = struct {
        const StorageType: storage.StorageType = .Sparse;
        val: u32,
    };

    var world = World.init(allocator);
    defer world.deinit();

    var entity = try world.spawn();
    try world.addComponentToEntity(entity, TestStruct{ .val = 42 });
    try world.addComponentToEntity(entity, TestStruct2{ .val = 99 });

    var removed_component: TestStruct = world.removeComponentFromEntity(TestStruct, entity).?;
    try testing.expectEqual(removed_component.val, 42);

    var removed_component2: TestStruct2 = world.removeComponentFromEntity(TestStruct2, entity).?;
    try testing.expectEqual(removed_component2.val, 99);
}
