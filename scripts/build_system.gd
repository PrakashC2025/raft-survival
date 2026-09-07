## Shared helper for the universal socket-to-socket attachment solver.
## Used by the build system to compute where a new piece must be placed so
## that its `new_piece_socket` exactly coincides with `target_socket` in
## world space.  Works for any piece type (foundation, wall, door, etc.).
##
## Returns a Transform3D suitable for assigning to the new piece's
## `global_transform`.
##
## Algorithm:
##   1. Compute the world-space offset from the new piece's center to its
##      attachment socket:  offset = new_piece_socket.position (local).
##   2. Rotate that offset by `build_rotation_y` around the global UP axis.
##   3. Place the piece center so that the rotated socket lands at the
##      target socket's global position:
##        center = target_socket.global_position - rotated_offset
##   4. The piece basis is the support piece's basis rotated by
##      `build_rotation_y`.
static func solve_socket_attachment(
	target_socket: Node3D,
	new_piece_socket_local_position: Vector3,
	build_rotation_y: float,
	support_basis: Basis,
) -> Transform3D:
	# 1. Local offset from piece center to attachment socket
	var local_offset: Vector3 = new_piece_socket_local_position

	# 2. Apply player build rotation (Y-axis only, around global UP)
	var rotated_offset: Vector3 = local_offset.rotated(Vector3.UP, build_rotation_y)

	# 3. Piece center in world space
	var piece_center: Vector3 = target_socket.global_position - rotated_offset

	# 4. Piece basis = support basis rotated by build rotation
	var piece_basis: Basis = support_basis.rotated(Vector3.UP, build_rotation_y)

	return Transform3D(piece_basis, piece_center)
