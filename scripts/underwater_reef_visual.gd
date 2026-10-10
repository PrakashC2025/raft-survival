extends RefCounted
## Original reusable reef geometry. No downloaded models or runtime textures.
static var _cache: Dictionary = {}

static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind): return _cache[kind]
	var s := SurfaceTool.new(); s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed=kind.hash()
	match kind:
		"Arch":
			for section in 18:
				var a := section*PI/18;var b := (section+1)*PI/18
				for ring in 10:
					var c := ring*TAU/10;var d := (ring+1)*TAU/10
					var points := [_arch_point(a,c),_arch_point(a,d),_arch_point(b,c),_arch_point(a,d),_arch_point(b,d),_arch_point(b,c)]
					for point in points:s.set_color(Color.WHITE);s.set_uv(Vector2.ZERO);s.add_vertex(point)
		"Sponge":
			for stem in 5:
				var at := Vector3(sin(stem*2.4)*.24,0,cos(stem*2.4)*.24)
				_tube(s,at,.10+rng.randf()*.045,.35+rng.randf()*.65,Color(.65,.32,.065))
		"BranchCoral":
			for stem in 9:
				var angle := stem*2.4
				var start := Vector3(sin(angle)*.16,0,cos(angle)*.16)
				var tip := start+Vector3(sin(angle)*.22,.35+rng.randf()*.4,cos(angle)*.22)
				_branch(s,start,tip,.035,Color(.46,.20,.47))
				for arm in 3:
					var joint := start.lerp(tip,.40+arm*.17)
					_branch(s,joint,joint+Vector3(sin(angle+arm)*.23,.18,cos(angle+arm)*.23),.018,Color(.56,.29,.53))
		"FanCoral":
			for arm in 13:
				var tip := Vector3((float(arm)/12-.5)*.9,.45+sin(float(arm)/12*PI)*.55,sin(arm*2.4)*.06)
				_branch(s,Vector3(0,.05,0),tip,.022,Color(.68,.25,.18))
		"BrainCoral":
			_sphere(s,Vector3(0,.2,0),Vector3(.4,.28,.36),Color(.63,.57,.29))
			for line in 8:
				var a := line*TAU/8
				var previous := Vector3(0,.48,0)
				for step in range(1,7):
					var b := step*PI/12
					var at := Vector3(cos(a+sin(b*9)*.10)*sin(b)*.40,.2+cos(b)*.28,sin(a+sin(b*9)*.10)*sin(b)*.36)
					_branch(s,previous,at,.017,Color(.42,.40,.19));previous=at
		"Urchin":
			_sphere(s,Vector3(0,.12,0),Vector3.ONE*.12,Color(.11,.055,.13),10,5)
			for spine in 28:
				var a := spine*2.4; var y := .12+float(spine%7)/8
				var direction := Vector3(cos(a)*sqrt(1-y*y),y,sin(a)*sqrt(1-y*y))
				_branch(s,Vector3(0,.12,0)+direction*.10,Vector3(0,.12,0)+direction*.32,.009,Color(.12,.075,.15))
		"Shell":
			_sphere(s,Vector3(0,.035,0),Vector3(.16,.055,.13),Color(.70,.62,.47),12,6)
			for ridge in 9:
				var a := -.7+ridge*.175
				_branch(s,Vector3(0,.04,-.09),Vector3(sin(a)*.14,.065,cos(a)*.13),.005,Color(.84,.77,.61))
		"Kelp":
			_branch(s,Vector3.ZERO,Vector3(.14,4.5,.08),.021,Color(.48,.47,.22))
			for leaf in 15:
				var y := .2+leaf*.27; var side := -1.0 if leaf%2==0 else 1.0
				_blade(s,Vector3(.03*y,y,0),Vector3(side*.72,.65,sin(leaf*2.4)*.35),.13)
		"Grass":
			for leaf in 7:
				var a := leaf*2.4
				_blade(s,Vector3.ZERO,Vector3(cos(a)*.22,.34+float(leaf%3)*.13,sin(a)*.22),.019)
		"Driftwood":
			_branch(s,Vector3(-.7,.15,-.08),Vector3(.8,.22,.10),.13,Color(.31,.25,.16))
			_branch(s,Vector3(.2,.18,0),Vector3(.5,.28,.4),.06,Color(.30,.24,.15))
		"Scrap":
			var box := BoxMesh.new();box.size=Vector3(.6,.08,.4)
			s.set_color(Color(.29,.22,.16));s.append_from(box,0,Transform3D(Basis.from_euler(Vector3(.15,.3,.18)),Vector3(0,.10,0)))
		"Container":
			var box := BoxMesh.new();box.size=Vector3(.7,.42,.48)
			s.set_color(Color(.33,.28,.19));s.append_from(box,0,Transform3D(Basis.IDENTITY,Vector3(0,.21,0)))
	s.generate_normals(); var result := s.commit(); _cache[kind]=result
	return result

static func _sphere(s: SurfaceTool, at: Vector3, size: Vector3, colour: Color, segments: int=10, rings: int=5) -> void:
	var sphere := SphereMesh.new(); sphere.radius=1; sphere.height=2; sphere.radial_segments=segments; sphere.rings=rings
	# append_from preserves the source's vertex channels; apply colour explicitly.
	var arrays := sphere.surface_get_arrays(0)
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for i in index:
		s.set_color(colour.srgb_to_linear());s.set_uv(Vector2.ZERO);s.add_vertex(at+points[i]*size)

static func _arch_point(angle: float, ring: float) -> Vector3:
	var wear := 1.0+sin(angle*17+ring*3)*.07+cos(angle*9-ring*2)*.04
	var radial := 4.5+cos(ring)*.92*wear
	return Vector3(cos(angle)*radial,.5+sin(angle)*radial,sin(ring)*2.25*wear)

static func _branch(s: SurfaceTool, start: Vector3, end: Vector3, radius: float, colour: Color) -> void:
	var direction := (end-start).normalized()
	var side := direction.cross(Vector3.FORWARD).normalized()
	if side.length_squared()<.1:side=Vector3.RIGHT
	var other := direction.cross(side).normalized()
	for segment in 7:
		var a := segment*TAU/7;var b := (segment+1)*TAU/7
		var pa := (cos(a)*side+sin(a)*other)*radius
		var pb := (cos(b)*side+sin(b)*other)*radius
		for point in [start+pa,start+pb,end+pa*.55,start+pb,end+pb*.55,end+pa*.55]:
			s.set_color(colour.srgb_to_linear());s.set_uv(Vector2.ZERO);s.add_vertex(point)

static func _tube(s: SurfaceTool, at: Vector3, radius: float, height: float, colour: Color) -> void:
	for segment in 12:
		var a := segment*TAU/12; var b := (segment+1)*TAU/12
		var lower_a := at+Vector3(cos(a)*radius,0,sin(a)*radius)
		var lower_b := at+Vector3(cos(b)*radius,0,sin(b)*radius)
		var upper_a := at+Vector3(cos(a)*radius*1.1,height,sin(a)*radius*1.1)
		var upper_b := at+Vector3(cos(b)*radius*1.1,height,sin(b)*radius*1.1)
		var inner_a := at+Vector3(cos(a)*radius*.75,height,sin(a)*radius*.75)
		var inner_b := at+Vector3(cos(b)*radius*.75,height,sin(b)*radius*.75)
		for point in [lower_a,lower_b,upper_a,lower_b,upper_b,upper_a,upper_a,upper_b,inner_a,upper_b,inner_b,inner_a]:
			s.set_color(colour.srgb_to_linear());s.set_uv(Vector2.ZERO);s.add_vertex(point)
		for point in [inner_a,inner_b,inner_a-Vector3.UP*height*.45,inner_b,inner_b-Vector3.UP*height*.45,inner_a-Vector3.UP*height*.45]:
			s.set_color(colour.darkened(.4).srgb_to_linear());s.set_uv(Vector2.ZERO);s.add_vertex(point)

static func _blade(s: SurfaceTool, at: Vector3, reach: Vector3, width: float) -> void:
	var side := Vector3(reach.z,0,-reach.x).normalized()
	for segment in 6:
		var a := float(segment)/6; var b := float(segment+1)/6
		var first := at+reach*Vector3(a*a,a,a*a);var last := at+reach*Vector3(b*b,b,b*b)
		var wa := width*sin(a*PI); var wb := width*sin(b*PI)
		var points := [first-side*wa,first+side*wa,last-side*wb,first+side*wa,last+side*wb,last-side*wb]
		var uv := [Vector2(0,a),Vector2(1,a),Vector2(0,b),Vector2(1,a),Vector2(1,b),Vector2(0,b)]
		for v in 6:s.set_color(Color.WHITE);s.set_uv(uv[v]);s.add_vertex(points[v])
