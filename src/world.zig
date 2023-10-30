const std = @import("std");
const storage = @import("./storage.zig");
const Allocator = std.mem.Allocator;
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

    allocator: Allocator,

    /// The total number of entities in the world.
    total_entities: usize = 0,

    /// Sparse component storages.
    sparse_components: Hashmap(ComponentHash, ErasedSparseStorage) = .{},

    /// Creates new `World`.
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Destroys the world and frees any allocations it made.
    pub fn deinit(self: *Self) void {
        // Free all sparse components
        for (self.sparse_components.keys()) |component_type| {
            var erased_storage: *ErasedSparseStorage = self.sparse_components.getPtr(component_type).?;
            erased_storage.deinit(erased_storage, self.allocator);
        }
        self.sparse_components.deinit(self.allocator);
    }

    /// Spawns an empty entity.
    pub fn spawn(self: *Self) !Entity {
        const entity = self.total_entities;
        self.total_entities += 1;

        // Add empty entry to all sparse components!
        for (self.sparse_components.keys()) |component_type| {
            var erased_storage: *ErasedSparseStorage = self.sparse_components.getPtr(component_type).?;
            try erased_storage.addEmptyEntity(erased_storage, self.allocator);
        }

        return entity;
    }

    /// Adds the specified component to the entity.
    pub fn addComponentToEntity(self: *Self, entity: Entity, component: anytype) !void {
        const ComponentType = @TypeOf(component);
        const COMPONENT_HASH = std.hash_map.hashString(@typeName(ComponentType));

        comptime {
            if (!@hasDecl(ComponentType, "StorageType")) {
                @compileError("The component type must have a `const StorageType: storage.StorageType` field");
            }
        }

        if (ComponentType.StorageType == storage.StorageType.Sparse) {
            // If component type exists already, then just update the existing value
            if (self.sparse_components.contains(COMPONENT_HASH)) {
                // Update the component value
                var erased_storage: *ErasedSparseStorage = self.sparse_components.getPtr(COMPONENT_HASH).?;
                erased_storage.updateValue(ComponentType, entity, component);
                return;
            }

            // Create new component type storage
            var new_storage = try ErasedSparseStorage.init(ComponentType, &self.allocator, self.total_entities);
            new_storage.updateValue(ComponentType, entity, component);
            try self.sparse_components.put(self.allocator, COMPONENT_HASH, new_storage);
        }

        // TODO: Add logic for dense/archetype storage
    }

    /// Removes the specified component type from the entity.
    pub fn removeComponentFromEntity(self: *Self, comptime Component: type, entity: Entity) ?Component {
        const COMPONENT_HASH = std.hash_map.hashString(@typeName(Component));

        if (Component.StorageType == .Sparse) {
            // Remove component if it exists for the specified component
            if (self.sparse_components.contains(COMPONENT_HASH)) {
                var concrete = ErasedSparseStorage.toConcrete(self.sparse_components.getPtr(COMPONENT_HASH).?.ptr, Component);
                var removed: Component = concrete.data.items[entity].?;
                concrete.data.items[entity] = null;
                return removed;
            }

            return null;
        }

        // TODO: Add `Dense` logic

    }

    /// Gets the entity's value for the component of the specified type.
    pub fn getComponentForEntity(self: *Self, comptime Component: type, entity: Entity) ?Component {
        if (Component.StorageType == .Sparse) {
            const COMPONENT_HASH = std.hash_map.hashString(@typeName(Component));

            var erased_storage: *ErasedSparseStorage = self.sparse_components.getPtr(COMPONENT_HASH).?;
            var concrete = ErasedSparseStorage.toConcrete(erased_storage.ptr, Component);
            return concrete.data.items[entity];
        }

        // TODO: Handle `Dense` storage
    }
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
