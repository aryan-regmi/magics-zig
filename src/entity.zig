const std = @import("std");
const storage = @import("storage.zig");
const ComponentHash = storage.ComponentHash;
const ArchetypeHash = storage.ArchetypeHash;

/// Represents the entity index.
pub const EntityId = usize;

/// An entity in the ECS.
pub const Entity = struct {
    id: EntityId,
};

/// Extra information about an entity and its location in the various storages.
pub const EntityMetadata = struct {
    /// Hash of the archetype the entity belongs to.
    archetype_hash: ArchetypeHash,

    /// Location in the `DenseStorage` where the entity's component values are stored.
    ///
    /// ## Note
    /// The location of the entity in the `SparseStorage` is the same as the entity's ID.
    dense_index: usize,

    /// The component types this entity has.
    component_types: std.ArrayListUnmanaged(ComponentHash),
};
