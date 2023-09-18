const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

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

/// Storage type that uses an `ArrayListUnmanaged` to store component values.
///
/// This storage type is optimized for fast insertions and deletions, but due to
/// its sparse nature, iterations will be slower than `DenseStorage`.
pub fn SparseStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        total_entites: usize,

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
    ptr: *anyopaque,

    deinit: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    /// Converts the type-erased storage to a typed `SparseStorage(Component)`.
    pub fn toConcreteStorage(ptr: *anyopaque, comptime Component: type) *SparseStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }
};
