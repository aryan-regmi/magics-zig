const std = @import("std");
// const entity = @import("entity.zig");
const Allocator = std.mem.Allocator;
// const EntityMetadata = entity.EntityMetadata;

/// Represents the type of storage.
///
/// `Dense` is optimized for fast iterations, while insertions and deletions are
/// slower.
///
/// `Sparse` is optimized for fast insertions and deletions, while iterations
/// are slower.
pub const StorageType = enum {
    Dense,
    Sparse,
};

/// Represents the hash for an archetype.
pub const ArchetypeHash = u64;

/// Represents the hash for a component type.
pub const ComponentHash = u64;

/// The hash for the empty (w/ no components) archetype.
pub const EMPTY_ARCHETYPE_HASH = std.math.maxInt(ArchetypeHash);

/// Storage type that uses an `ArrayListUnmanaged` to store component values.
///
/// This storage type is optimized for fast insertions and deletions, but due to
/// its sparse nature, iterations will be slower than `DenseStorage`.
pub fn SparseStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// Total number of entites in the storage.
        ///
        ///
        /// ## Note
        /// This should be equal to the number of entites in the world.
        total_entites: usize,

        /// The actual component values of `Component` type.
        ///
        /// Each index represents an entity with the corresponding ID:
        /// components[1] = component value for Entity 1.
        components: std.ArrayListUnmanaged(?Component),

        /// Free the memory used by the `SparseStorage`.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.components.deinit(allocator);
            self.total_entites = 0;
        }

        /// Adds an empty (`null`) entry to the component list.
        ///
        /// This indicates that a new entity has been added to the world.
        pub fn addEmptyEntry(self: *Self, allocator: Allocator) !void {
            try self.components.append(allocator, null);
            self.total_entites += 1;
        }

        /// Sets the component value at the specified index.
        pub fn setComponentValue(self: *Self, index: usize, value: Component) void {
            self.components.items[index] = value;
        }
    };
}

/// A type-erased `SparseStorage`.
pub const ErasedSparseStorage = struct {
    /// A pointer to the underyling `SparseStorage`.
    ptr: *anyopaque,

    /// Frees memory used by the underyling `SparseStorage`.
    deinit: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    /// Adds an empty (`null`) entry to the component list.
    ///
    /// This indicates that a new entity has been added to the world.
    addEmptyEntry: *const fn (ptr: *anyopaque, allocator: Allocator) anyerror!void,

    /// Converts the type-erased storage to a typed `SparseStorage(Component)`.
    pub fn toSparseStorage(ptr: *anyopaque, comptime Component: type) *SparseStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }
};

/// Storage type that stores component values densely to optimize iteration rather than insertion/deletion.
pub fn DenseStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// Total number of entites in the storage.
        total_entites: usize,

        /// The densely stored component values/data.
        ///
        /// Each index represents an entity with a `Component` value: entities without a component value are ignored.
        components: std.ArrayListUnmanaged(Component),

        /// Free the memory used by the `DenseStorage`.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.components.deinit(allocator);
            self.total_entites = 0;
        }

        /// Adds a new entity to the dense storage with the given component value.
        pub fn addNewEntityWithComponentValue(self: *Self, allocator: Allocator, component: Component) !void {
            self.components.append(allocator, component);
            self.total_entites += 1;
        }
    };
}

/// A type-erased `DenseStorage`.
pub const ErasedDenseStorage = struct {
    const Self = @This();

    /// A pointer to the underyling `DenseStorage`.
    ptr: *anyopaque,

    /// Total number of entites in the storage.
    total_entites: usize,

    /// Frees memory used by the underyling `DenseStorage`.
    deinit: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    /// Moves an entity from the `src` storage to the `dst` storage.
    ///
    /// ## Note
    /// The `src` and `dst` storages must be the same underlying type
    /// (`DenseStorage(T)`, where T is the same component for both storages).
    moveEntity: *const fn (src: *Self, dst: *Self, src_idx: usize) void,

    /// Converts the type-erased storage to a typed `DenseStorage(Component)`.
    pub fn toDenseStorage(ptr: *anyopaque, comptime Component: type) *DenseStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }
};

/// Archetype storage that emulates an in-memory database to store groups of
/// component values.
///
/// This storage type is optimized for fast iterations, but has slower
/// insertions and deletions than `SparseStorage`.
pub const ArchetypeStorage = struct {
    const Self = @This();
    /// The hash for the archetype (uniquely identifies different archetypes).
    hash: ArchetypeHash,

    /// Total number of entites with this archetype.
    total_entites: usize,

    /// The densely stored component data for each of the component types in the archetype.
    dense_components: std.AutoArrayHashMapUnmanaged(ComponentHash, ErasedDenseStorage),

    /// The sparsely stored components for each of the non-dense component types in the archetype.
    sparse_components: std.AutoArrayHashMapUnmanaged(ComponentHash, *const ErasedSparseStorage),

    /// Free the memory used by the `ArchetypeStorage`.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        // Deinit ErasedDenseStorages
        for (self.dense_components.values()) |dense_storage| {
            dense_storage.deinit(dense_storage.ptr, allocator);
        }

        self.dense_components.deinit(allocator);
        self.sparse_components.deinit(allocator);
        self.total_entites = 0;
    }

    /// Moves an entity from `this`/`self` dense storage to the `other` storage.
    pub fn moveEntity(self: *Self, other: *Self, src_idx: usize) !void {
        // Move component from `self` dense storage if `other` has `component_type`.
        for (self.dense_components.keys()) |component_type| {
            var src_storage: *ErasedDenseStorage = self.dense_components.getPtr(component_type).?;
            if (other.dense_components.contains(component_type)) {
                var dst_storage: *ErasedDenseStorage = other.dense_components.getPtr(component_type).?;
                src_storage.moveEntity(src_storage, dst_storage, src_idx);
            }
        }

        self.total_entites -= 1;
        other.total_entites += 1;
    }
};
