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

    /// Converts the type-erased storage to a typed `SparseStorage(Component)`.
    pub fn toSparseStorage(ptr: *anyopaque, comptime Component: type) *SparseStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }
};

/// Archetype storage that emulates an in-memory database to store groups of
/// component values.
///
/// This storage type is optimized for fast iterations, but has slower
/// insertions and deletions than `SparseStorage`.
pub fn DenseStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// The hash for the archetype (uniquely identifies different archetypes).
        hash: ArchetypeHash,

        /// Total number of entites in the storage.
        total_entites: usize,

        /// The densely stored component values for each of the component types in the archetype.
        components: std.AutoArrayHashMapUnmanaged(ComponentHash, std.ArrayListUnmanaged(Component)),

        /// Free the memory used by the `DenseStorage`.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.components.deinit(allocator);
            self.total_entites = 0;
        }

        /// Moves an entity from `this`/`self` dense storage to the `other` storage.
        pub fn moveEntity(self: *Self, other: *Self, src_idx: usize, dst_idx: usize) void {
            for (self.components.keys()) |component_type| {
                if (other.components.contains(component_type)) {
                    var component_vals = self.components.getPtr(component_type).?;
                    var val_to_move = component_vals.items[src_idx];
                    component_vals.items[src_idx] = null;

                    var other_vals = other.components.getPtr(component_type).?;
                    other_vals.items[dst_idx] = val_to_move;
                }
            }
        }
    };
}

/// A type-erased `DenseStorage`.
pub const ErasedDenseStorage = struct {
    /// A pointer to the underyling `DenseStorage`.
    ptr: *anyopaque,

    /// Frees memory used by the underyling `DenseStorage`.
    deinit: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    /// Converts the type-erased storage to a typed `DenseStorage(Component)`.
    pub fn toDenseStorage(ptr: *anyopaque, comptime Component: type) *DenseStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }
};
