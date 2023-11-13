const std = @import("std");
const world = @import("world.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const HashMap = std.AutoArrayHashMapUnmanaged;
const Entity = world.Entity;
const ComponentHash = world.ComponentHash;
const ArchetypeHash = world.ArchetypeHash;

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
///
/// This is optimized for insertions and deletions.
pub fn SparseComponentStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// The sparsely stored component data.
        _data: ArrayList(?Component) = .{},

        /// Create new `SparseComponentStorage`.
        pub fn init(allocator: Allocator, num_entities: usize) !Self {
            // Create new array list and initalize values to `null`
            var data = try ArrayList(?Component).initCapacity(allocator, num_entities);
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

    // TODO: Add func to check if value exists for an entity
    _valueExists: *const fn (self: *Self, entity: Entity) bool,

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
            ._valueExists = (struct {
                pub fn valueExists(self: *Self, entity: Entity) bool {
                    var concrete = self.toConcrete(Component);
                    return concrete._data.items[entity] != null;
                }
            }).valueExists,
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

    /// Casts the erased sparse storage to its concrete type.
    pub fn toConcrete(self: *Self, comptime Component: type) *SparseComponentStorage(Component) {
        return @ptrCast(@alignCast(self._ptr));
    }

    // Adds an empty entry for an entity in the storage.
    pub fn addEmptyEntity(self: *Self, allocator: Allocator) !void {
        try self._addEmptyEntity(self, allocator);
    }

    /// Removes the entity from the storage when the storage type is unknown.
    pub fn removeEntityErased(self: *Self, entity: Entity) ?void {
        return self._removeEntityErased(self, entity);
    }

    /// Checks if a value exists.
    pub fn valueExists(self: *Self, entity: Entity) bool {
        return self._valueExists(self, entity);
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

/// Storage for a single type of component, where the entity data is stored densely.
///
/// This is optimized for iteration, while insertions and deletions are slower.
pub fn DenseComponentStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        /// The densely stored component data.
        _data: ArrayList(Component) = .{},

        /// Create new `DenseComponentStorage`.
        pub fn init(allocator: Allocator, num_entities: usize) !Self {
            var data = try ArrayList(Component).initCapacity(allocator, num_entities);
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

/// A type erased `DenseComponentStorage` for optimized for dense storage.
pub const ErasedDenseStorage = struct {
    const Self = @This();

    /// Points the the concrete `DenseComponentStorage`.
    _ptr: *anyopaque,

    /// Frees memory used by the storage.
    _deinit: *const fn (self: *Self, allocator: Allocator) void,

    /// Initialize a new dense storage, return the dense storage pointing at it.
    pub fn init(comptime Component: type, allocator: Allocator, num_entities: usize) !Self {
        var ptr = try allocator.create(DenseComponentStorage(Component));
        ptr.* = try DenseComponentStorage(Component).init(allocator, num_entities);

        return .{
            ._ptr = ptr,
            ._deinit = (struct {
                pub fn deinit(self: *Self, allocator_: Allocator) void {
                    var concrete = self.toConcrete(Component);
                    concrete.deinit(allocator_);
                    allocator_.destroy(concrete);
                }
            }).deinit,
        };
    }

    /// Frees the memory used by the underlying dense storage.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self._deinit(self, allocator);
    }

    /// Casts the erased dense storage to its concrete type.
    pub fn toConcrete(self: *Self, comptime Component: type) *DenseComponentStorage(Component) {
        return @ptrCast(@alignCast(self._ptr));
    }

    /// Updates the component value at the given index.
    pub fn updateValue(self: *Self, comptime Component: type, idx: usize, component: Component) void {
        var concrete = self.toConcrete(Component);
        concrete._data[idx] = component;
    }
};

/// Storage for archetypes.
pub const ArchetypeStorage = struct {
    const Self = @This();

    /// The identifying hash of the archetype.
    _hash: ArchetypeHash,

    /// The number of components with this archetype.
    _num_components: usize = 0,

    /// A list of references to sparse component storages of the archetype.
    _sparse_components: ArrayList(*ErasedSparseStorage) = .{},

    /// The dense component storages of the archetype.
    _dense_components: HashMap(ComponentHash, ErasedDenseStorage) = .{},

    /// List of component types in the archetype.
    _component_types: ArrayList(ComponentHash) = .{},

    /// Creates new (empty) archetype storage.
    pub fn init(hash: u64) Self {
        return Self{ ._hash = hash };
    }

    /// Frees the memory used by the archetype storage.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        // Free sparse components
        self._sparse_components.deinit(allocator);

        // Free dense components
        for (self._dense_components.keys()) |component_type| {
            var dense_component: *ErasedDenseStorage = self._dense_components.getPtr(component_type).?;
            dense_component.deinit(allocator);
        }
        self._dense_components.deinit(allocator);
    }

    /// Gets the hash of the archetype.
    pub fn getHash(self: *Self) ArchetypeHash {
        return self._hash;
    }

    /// Gets the number of components in the archetype.
    pub fn getNumComponents(self: *Self) usize {
        return self._num_components;
    }

    /// Checks if the archetype has the specified component.
    pub fn hasComponentType(self: *Self, component_hash: ComponentHash) bool {
        for (self._component_types) |component_type| {
            if (component_type == component_hash) {
                return true;
            }
        }
        return false;
    }

    /// Updates the component value at the given index.
    pub fn updateComponentValue(self: *Self, comptime Component: type, idx: usize, component: Component) void {
        const COMPONENT_HASH = std.hash_map.hashString(@typeName(Component));
        var dense_storage: *ErasedDenseStorage = self._dense_components.getPtr(COMPONENT_HASH).?;
        dense_storage.updateValue(Component, idx, component);
    }
};

/// Hash of empty archetype.
pub const EMPTY_ARCHETYPE_HASH = std.math.maxInt(u64);
