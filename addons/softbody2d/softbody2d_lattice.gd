@tool
class_name SoftBody2DLattice
extends RefCounted

## Topology of a [SoftBody2D]'s bodies: who is jointed to whom, which connected pieces
## exist, and the best rigid fit of a group onto its rest layout. Owned by the softbody and
## rebuilt lazily whenever joints change.

var _softbody: SoftBody2D
var _clusters: Array = []
var _dirty := true
var _rest_position := PackedVector2Array()
var _rest_rotation := PackedFloat32Array()
var _positions := PackedVector2Array()
var _awake := PackedByteArray()
var _frame_parity := 0
var _neighbours: Array[PackedInt32Array] = []


func _init(softbody: SoftBody2D) -> void:
	_softbody = softbody


## Call after joints were added or removed.
func invalidate() -> void:
	_dirty = true


## Call after the softbody was cleared or regenerated.
func reset() -> void:
	_clusters = []
	_dirty = true
	_rest_position.clear()
	_rest_rotation.clear()
	_neighbours.clear()


## Connected groups of bodies, as arrays of indices into [method SoftBody2D.get_rigid_bodies].
func get_cluster_indices() -> Array:
	_ensure()
	return _clusters


## Rotates every bone with the best rigid fit of its own neighbourhood, so adjacent regions
## agree on how the skin bends. [param base_rotation] is the softbody's global rotation,
## since fits are made against global body positions.
## Hot path: it runs for every body every drawn frame, so it works on packed arrays and
## allocates nothing, skips bones whose whole neighbourhood is asleep, and fits only half of
## the awake bones per frame, alternating, which no eye can tell at 60 frames per second.
func update_skin_rotations(base_rotation: float) -> void:
	_ensure()
	var bodies := _softbody.get_rigid_bodies()
	var count := bodies.size()
	if count == 0 || _neighbours.size() != count:
		return
	if _positions.size() != count:
		_positions.resize(count)
		_awake.resize(count)
	for i in count:
		var body := bodies[i].rigidbody as RigidBody2D
		if body == null || !body.is_inside_tree():
			_awake[i] = 0
			continue
		_positions[i] = body.global_position
		_awake[i] = 0 if body.sleeping || body.freeze else 1
	_frame_parity = 1 - _frame_parity
	for i in range(_frame_parity, count, 2):
		var ring := _neighbours[i]
		var ring_size := ring.size()
		if ring_size < 2:
			continue
		var moving := false
		for idx in ring:
			if _awake[idx] == 1:
				moving = true
				break
		if !moving:
			continue
		var centre := Vector2.ZERO
		var rest_centre := Vector2.ZERO
		for idx in ring:
			centre += _positions[idx]
			rest_centre += _rest_position[idx]
		centre /= ring_size
		rest_centre /= ring_size
		var sin_sum := 0.0
		var cos_sum := 0.0
		for idx in ring:
			var rest := _rest_position[idx] - rest_centre
			var current := _positions[idx] - centre
			sin_sum += rest.cross(current)
			cos_sum += rest.dot(current)
		var rotation := _rest_rotation[i] + atan2(sin_sum, cos_sum) - base_rotation
		var bone := bodies[i].bone
		if bone && absf(bone.rotation - rotation) > 0.0005:
			bone.rotation = rotation


func _ensure() -> void:
	if !_dirty:
		return
	_dirty = false
	var bodies := _softbody.get_rigid_bodies()
	var count := bodies.size()
	_clusters = []
	if count == 0:
		return
	if _rest_position.size() != count:
		_rest_position.resize(count)
		_rest_rotation.resize(count)
		for i in count:
			var body := bodies[i].rigidbody
			_rest_position[i] = body.get_meta("rest_position", body.position)
			_rest_rotation[i] = bodies[i].bone.rest.get_rotation() if bodies[i].bone else 0.0
	var body_index := {}
	for i in count:
		body_index[bodies[i].rigidbody.get_instance_id()] = i
	_neighbours.clear()
	_neighbours.resize(count)
	for i in count:
		_neighbours[i] = PackedInt32Array([i])
	# Joints are parented to one body of a pair; a ring must see the pair from both sides.
	for i in count:
		for joint in bodies[i].joints:
			if joint == null || joint.is_queued_for_deletion():
				continue
			var target := _softbody.get_joint_target(joint)
			if target == null:
				continue
			var j: int = body_index.get(target.get_instance_id(), -1)
			if j < 0:
				continue
			if !_neighbours[i].has(j):
				_neighbours[i].append(j)
			if !_neighbours[j].has(i):
				_neighbours[j].append(i)
	_clusters = _connected_groups(count)


# Union-find over the neighbour rings.
func _connected_groups(count: int) -> Array:
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	for i in count:
		for j in _neighbours[i]:
			var root_i := _find_root(parent, i)
			var root_j := _find_root(parent, j)
			if root_i != root_j:
				parent[root_j] = root_i
	var groups := {}
	for i in count:
		var root := _find_root(parent, i)
		if !groups.has(root):
			groups[root] = PackedInt32Array()
		groups[root].append(i)
	return groups.values()


func _find_root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
