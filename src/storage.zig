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
        _data: ArrayListUnmanaged(?Component) = .{},

        /// Create new `SparseComponentStorage`.
        pub fn init(allocator: Allocator, num_entities: usize) !Self {
            // Create new array list and initalize values to `null`
            var data = try ArrayListUnmanaged(?Component).initCapacity(allocator, num_entities);
            for (0..num_entities) |_| {
                try data.append(allocator, null);
            }

            return .{
                ._data = data,
            };
        }

        /// Frees memory used by the storage.
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self._data.deinit(allocator);
        }
    };
}

/// A type erased `SparseComponentStorage` for optimized for sparse storage.
pub const ErasedSparseStorage = struct {
    const Self = @This();

    /// Points the the concrete `SparseComponentStorage`.
    _ptr: *anyopaque,

    /// Adds an empty entry in the storage.
    _addEmptyEntity: *const fn (self: *Self, allocator: Allocator) anyerror!void,

    /// Removes an entity from the storage if component type is unknown.
    _removeEntityErased: *const fn (self: *Self, entity: Entity) ?void,

    // // Gets the component value for the specified entity.
    // _getComponentValue: *const fn (self: *Self, comptime Compo entity: Entity) type,

    /// Frees memory used by the storage.
    _deinit: *const fn (self: *Self, allocator: Allocator) void,

    /// Initialize a new sparsed storage, return the erased storage pointing at it.
    pub fn init(comptime Component: type, allocator: Allocator, num_entities: usize) !Self {
        var ptr = try allocator.create(SparseComponentStorage(Component));
        ptr.* = try SparseComponentStorage(Component).init(allocator, num_entities);

        return .{
            ._ptr = ptr,
            ._addEmptyEntity = (struct {
                pub fn addEmptyEntity(self: *Self, allocator_: Allocator) anyerror!void {
                    var concrete = self.toConcrete(Component);
                    try concrete._data.append(allocator_, null);
                }
            }).addEmptyEntity,
            ._removeEntityErased = (struct {
                pub fn removeEntityErased(self: *Self, entity: Entity) ?void {
                    _ = self.removeEntity(Component, entity) orelse return null;
                }
            }).removeEntityErased,
            ._deinit = (struct {
                pub fn deinit(self: *Self, allocator_: Allocator) void {
                    var concrete = self.toConcrete(Component);
                    concrete.deinit(allocator_);
                    allocator_.destroy(concrete);
                }
            }).deinit,
        };
    }

    /// Frees the memory used by the underlying sparse storage.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self._deinit(self, allocator);
    }

    // Adds an empty entry for an entity in the storage.
    pub fn addEmptyEntity(self: *Self, allocator: Allocator) !void {
        try self._addEmptyEntity(self, allocator);
    }

    /// Removes the entity from the storage when the storage type is unknown.
    pub fn removeEntityErased(self: *Self, entity: Entity) ?void {
        return self._removeEntityErased(self, entity);
    }

    /// Casts the erased sparse storage to its concrete type.
    pub fn toConcrete(self: *Self, comptime Component: type) *SparseComponentStorage(Component) {
        return @ptrCast(@alignCast(self._ptr));
    }

    /// Updates the component value to `component` for the given entity.
    pub fn updateValue(self: *Self, comptime Component: type, entity: Entity, component: Component) void {
        var concrete = self.toConcrete(Component);
        concrete._data.items[entity] = component;
    }

    /// Removes an entity from the component storage.
    pub fn removeEntity(self: *Self, comptime Component: type, entity: Entity) ?Component {
        // Convert to concrete storage
        var concrete = self.toConcrete(Component);

        // Remove and return the current component for the specified entity
        var removed: Component = concrete._data.items[entity] orelse return null;
        concrete._data.items[entity] = null;
        return removed;
    }
};
