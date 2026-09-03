extends Marker3D
class_name BuildSocket

# What kind of socket this is (informational; placement uses `accepts`).
enum SocketType {
	FOUNDATION_EDGE,
	FOUNDATION_TOP,
	WALL_BASE,
	WALL_TOP,
	WALL_SIDE,
	DOOR_SLOT,
	WINDOW_SLOT,
	PILLAR_TOP,
}

@export var socket_type: SocketType = SocketType.FOUNDATION_EDGE
# Which piece names this socket can host. Empty array means "compatible with
# anything" (use sparingly — explicit lists prevent cross-type mis-snaps).
@export var accepts: Array[String] = []

var is_occupied: bool = false
var occupying_piece: Node3D = null

func occupy(piece: Node3D) -> void:
	is_occupied = true
	occupying_piece = piece

func free_socket() -> void:
	is_occupied = false
	occupying_piece = null

# Walk up the tree to find the actual raft root this socket lives on.
func get_parent_raft() -> Node3D:
	var n: Node = self
	while n != null:
		if n.is_in_group("build_surface"):
			return n as Node3D
		n = n.get_parent()
	return null

# The piece this socket belongs to (its direct great-grandparent's parent,
# or whatever ancestor is the actual placed piece root).
func get_parent_piece() -> Node3D:
	var n: Node = self
	while n != null:
		# Skip until we find a node that has BuildSockets as a direct child.
		var sockets := n.get_node_or_null("BuildSockets")
		if sockets != null and self.get_parent() == sockets:
			return n as Node3D
		n = n.get_parent()
	return null

func is_compatible(piece_name: String) -> bool:
	return accepts.is_empty() or accepts.has(piece_name)
