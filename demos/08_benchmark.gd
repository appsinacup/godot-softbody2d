extends "res://demos/shared/demo_base.gd"

## Benchmark: keep spawning softbodies until a limit and watch what happens to the frame
## rate, so you know how many this machine can carry.

const SPAWN_INTERVAL := 0.75
const FPS_FLOOR := 30.0
## Generating a softbody is a spike of its own; the frame rate is sampled only this long
## after a spawn, so the number says how the softbodies run, not how fast they are built.
const SETTLE_AFTER_SPAWN := 0.35

var _limit := 40
var _vertex_interval := 40
var _reach := 2
var _ticks_per_second := 60
var _stop_at_fps_floor := true
var _running := false
var _since_spawn := 0.0
var _peak_softbodies := 0
var _fps_samples: Array[float] = []
var _auto_reported := {}
var _last_generation_ms := 0.0


func demo_title() -> String:
	return "8. Benchmark"


func _init() -> void:
	arena = Rect2(-900, -500, 1800, 1000)


func build() -> void:
	Engine.physics_ticks_per_second = _ticks_per_second
	_running = false
	if "--benchmark-auto" in OS.get_cmdline_user_args():
		_auto_run()
	_since_spawn = 0.0
	_peak_softbodies = 0
	_fps_samples.clear()
	if controls.get_child_count() == 0:
		add_slider("Spawn up to", 1.0, 200.0, _limit, func(v: float): _limit = int(v), 1.0)
		add_slider(
			"Vertex interval (bodies per softbody)",
			20.0,
			80.0,
			_vertex_interval,
			func(v: float): _vertex_interval = int(v),
			5.0
		)
		add_slider("Joint reach (hops)", 1.0, 3.0, _reach, func(v: float): _reach = int(v), 1.0)
		add_slider(
			"Physics ticks per second",
			30.0,
			240.0,
			_ticks_per_second,
			func(v: float):
				_ticks_per_second = int(v)
				Engine.physics_ticks_per_second = _ticks_per_second,
			30.0
		)
		add_toggle("Stop when frame rate falls under 30", _stop_at_fps_floor, func(v: bool): _stop_at_fps_floor = v)
		add_shape_toggle()
		add_separator()
		add_button("Start", func(): _running = true)
		add_button("Pause", func(): _running = false)
		add_button("Reset (R)", reset_demo)
		add_readout(
			func():
				return "frame rate: %.0f fps at %d physics ticks/s" % [_smoothed_fps(), Engine.physics_ticks_per_second]
		)
		add_readout(
			func():
				return (
					"physics: %.1f ms per frame" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
				)
		)
		add_readout(func(): return "softbodies: %d  (peak %d)" % [_softbodies().size(), _peak_softbodies])
		add_readout(func(): return "bodies: %d   joints: %d" % [_body_count(), total_joints()])
		add_readout(func(): return "last softbody took %.0f ms to generate" % _last_generation_ms)
		add_readout(func(): return _verdict())
	set_status("Press Start.")


func _exit_tree() -> void:
	Engine.physics_ticks_per_second = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)


func _physics_process(delta: float) -> void:
	super(delta)
	_since_spawn += delta
	if _since_spawn >= SETTLE_AFTER_SPAWN:
		_fps_samples.append(Engine.get_frames_per_second())
		if _fps_samples.size() > 20:
			_fps_samples.pop_front()
	if "--benchmark-auto" in OS.get_cmdline_user_args() and _fps_samples.size() >= 20:
		_auto_report()
	if not _running:
		return
	var count := _softbodies().size()
	_peak_softbodies = maxi(_peak_softbodies, count)
	if count >= _limit:
		_running = false
		set_status("Reached the limit of %d softbodies." % _limit)
		return
	if _stop_at_fps_floor and count > 0 and _fps_samples.size() >= 10 and _smoothed_fps() < FPS_FLOOR:
		_running = false
		set_status("Frame rate fell under %.0f at %d softbodies." % [FPS_FLOOR, count])
		return
	if _since_spawn >= SPAWN_INTERVAL and _fps_samples.size() >= 10:
		_since_spawn = 0.0
		_fps_samples.clear()
		_spawn_one()


# `godot res://demos/08_benchmark.tscn -- --benchmark-auto [--interval=N] [--reach=N] [--ticks=N]`:
# keeps spawning with vsync off, prints when the frame rate first falls under 60 and under
# 30, then quits.
func _auto_run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--interval="):
			_vertex_interval = int(arg.get_slice("=", 1))
		elif arg.begins_with("--reach="):
			_reach = int(arg.get_slice("=", 1))
		elif arg.begins_with("--ticks="):
			_ticks_per_second = int(arg.get_slice("=", 1))
			Engine.physics_ticks_per_second = _ticks_per_second
	_limit = 400
	_stop_at_fps_floor = false
	_running = true


func _auto_report() -> void:
	var fps := _smoothed_fps()
	var count := _softbodies().size()
	for floor_fps in [60.0, 30.0]:
		if fps < floor_fps and count > 2 and not _auto_reported.has(floor_fps):
			_auto_reported[floor_fps] = true
			print(
				(
					"BENCHMARK interval %d reach %d %d ticks/s: under %.0f fps at %d softbodies (%d bodies, %d joints)"
					% [
						_vertex_interval,
						_reach,
						Engine.physics_ticks_per_second,
						floor_fps,
						count,
						_body_count(),
						total_joints()
					]
				)
			)
	if _auto_reported.has(30.0):
		get_tree().quit()


func _spawn_one() -> void:
	var x := randf_range(arena.position.x + 150.0, arena.end.x - 150.0)
	var started := Time.get_ticks_usec()
	spawn_softbody(
		Vector2(x, arena.position.y + 120.0),
		func(sb: SoftBody2D):
			sb.vertex_interval = _vertex_interval
			sb.radius = _vertex_interval * 0.95
			sb.joint_reach = _reach
			sb.gravity_scale = 1.0
			sb.can_sleep = true
	)
	_last_generation_ms = (Time.get_ticks_usec() - started) / 1000.0


func _smoothed_fps() -> float:
	if _fps_samples.is_empty():
		return Engine.get_frames_per_second()
	var total := 0.0
	for f in _fps_samples:
		total += f
	return total / _fps_samples.size()


func _body_count() -> int:
	var n := 0
	for sb in _softbodies():
		n += sb.get_rigid_bodies().size()
	return n


func _verdict() -> String:
	if _running:
		return "spawning..."
	if _peak_softbodies == 0:
		return ""
	return "stopped at %d softbodies, %d bodies, %d joints" % [_softbodies().size(), _body_count(), total_joints()]
