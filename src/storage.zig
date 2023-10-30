const std = @import("std");
const world = @import("world.zig");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Entity = world.Entity;

/// Determines the type of storage for a component type.
///
/// `Sparse` storage is optimized for fast insertions and deletions, but
/// iterating over the components will be slower.
/// `Dense` storage is optimized for fast iterations, but insertions and
/// deletions will be slower.
///
/// If you are unsure what type of storage to use for a component type, default
/// it to to `Dense`, and change it only if you notice significant difference in
/// performance.
pub const StorageType = enum { Sparse, Dense };

/// Storage for a single type of component, where the entity data is stored sparsely.
pub fn SparseComponentStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// The sparsely stored component data.
        data: ArrayListUnmanaged(?Component) = .{},

        /// Create new `SparseComponentStorage`.
        pub fn init(allocator: Allocator, num_entities: usize) !Self {
            // Create new array list and initalize values to `null`
            var data = try ArrayListUnmanaged(?Component).initCapacity(allocator, num_entities);
            for (0..num_entities) |_| {
                try data.append(allocator, null);
            }

            return .{
                .data = data,
            };
        }

        /// Frees memory used by the storage.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.data.deinit(allocator);
        }
    };
}

/// A type erased `SparseComponentStorage` for optimized for sparse storage.
pub const ErasedSparseStorage = struct {
    const Self = @This();

    /// Points the the concrete `SparseComponentStorage`.
    ptr: *anyopaque,

    /// Function to add an empty entry in the storage.
    addEmptyEntity: *const fn (self: *Self, allocator: Allocator) anyerror!void,

    /// Frees memory used by the storage.
    deinit: *const fn (self: *Self, allocator: Allocator) void,

    /// Initialize a new sparsed storage, return the erased storage pointing at it.
    pub fn init(comptime Component: type, allocator: Allocator, num_entities: usize) !Self {
        var ptr = try allocator.create(SparseComponentStorage(Component));
        ptr.* = try SparseComponentStorage(Component).init(allocator, num_entities);

        return .{
            .ptr = ptr,
            .addEmptyEntity = (struct {
                pub fn addEmptyEntity(self: *Self, allocator_: Allocator) anyerror!void {
                    var concrete = Self.toConcrete(self.ptr, Component);
                    try concrete.data.append(allocator_, null);
                }
            }).addEmptyEntity,
            .deinit = (struct {
                pub fn deinit(self: *Self, allocator_: Allocator) void {
                    var concrete = Self.toConcrete(self.ptr, Component);
                    concrete.deinit(allocator_);
                    allocator_.destroy(concrete);
                }
            }).deinit,
        };
    }

    /// Casts the erased sparse storage to its concrete type.
    pub fn toConcrete(ptr: *anyopaque, comptime Component: type) *SparseComponentStorage(Component) {
        return @ptrCast(@alignCast(ptr));
    }

    /// Updates the component value for to `component` fo the given entity.
    pub fn updateValue(self: *Self, comptime Component: type, entity: Entity, component: Component) void {
        var concrete = Self.toConcrete(self.ptr, Component);
        concrete.data.items[entity] = component;
    }
};
