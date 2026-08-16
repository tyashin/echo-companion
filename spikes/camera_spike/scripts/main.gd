extends Control
## Phase 0.2 camera spike (implementation_plan.md §0.2).
##
## Measures the full naive GDScript camera path on the target tablet:
##   CameraServer/CameraFeed -> CameraTexture.get_image() readback -> JPEG encode
## Per-second metrics (rates, stage timings, CPU, thermal) are appended to a CSV
## in user://; a JSON summary is written when the run stops. Throwaway harness —
## the commit-or-abandon decision for the vision path is made from its numbers.
##
## CLI: `-- --self-test` runs a 6-second benchmark and quits (headless smoke test).

const RUN_DURATION_S := 1800.0  # 30-minute benchmark run (per the plan)
const RATE_PRESETS: Array[float] = [5.0, 10.0, 15.0, 30.0, 0.0]  # 0.0 = MAX (every process frame)
const RES_PRESETS: Array[Vector2i] = [Vector2i(640, 480), Vector2i(1280, 720), Vector2i(1920, 1080)]
const JPEG_QUALITY := 0.8
const USER_HZ := 100.0  # Linux/Android clock ticks per second used by /proc/*/stat
const CSV_HEADER := "elapsed_s,state,render_fps,feed_fps,extracted_fps,target_fps,width,height,read_ms_avg,read_ms_max,enc_ms_avg,enc_ms_max,enc_kb_avg,proc_cpu_pct,total_cpu_pct,mem_mb,temp_c,errors"

var _feed: CameraFeed
var _cam_idx := 0
var _cam_texture: CameraTexture
var _readback_path := "none"  # "get_image" or "texture_2d_get" — which readback works

var _running := false
var _elapsed := 0.0
var _run_limit_s := RUN_DURATION_S
var _self_test := false

var _rate_idx := 1  # default 10 fps
var _res_idx := 1   # default 1280x720
var _max_mode := false
var _extract_interval := 0.1
var _since_extract := 0.0

var _sec_timer := 0.0
var _acquire_timer := 0.0
var _feed_frames := 0    # frame_changed count in the current second
var _extracted := 0      # extractions in the current second
var _errors := 0
var _sec_read: Array[float] = []
var _sec_enc: Array[float] = []
var _sec_enc_kb: Array[float] = []
var _read_ms: Array[float] = []  # per-extraction timings for the whole run
var _enc_ms: Array[float] = []

var _prev_proc_ticks := -1
var _prev_proc_time := 0.0
var _prev_cpu_total := -1
var _prev_cpu_idle := -1
var _temp_files: Array[String] = []

var _csv: FileAccess
var _csv_path := ""
var _status_msg := "starting"

var _preview: TextureRect
var _stats: Label
var _btn_start: Button
var _btn_rate: Button
var _btn_res: Button
var _btn_cam: Button


func _ready() -> void:
	_build_ui()
	_init_thermal()
	_self_test = "--self-test" in OS.get_cmdline_user_args()
	CameraServer.monitoring_feeds = true
	CameraServer.camera_feed_added.connect(_on_feed_added)
	CameraServer.camera_feed_removed.connect(_on_feed_removed)
	if OS.has_feature("android"):
		# Shows the runtime permission dialog unless already granted.
		OS.request_permissions()
	_cam_texture = CameraTexture.new()
	_preview.texture = _cam_texture
	print("user:// -> %s" % ProjectSettings.globalize_path("user://"))
	if _self_test:
		_run_limit_s = 6.0
		_start_run()


func _process(delta: float) -> void:
	if _feed == null:
		_acquire_timer += delta
		if _acquire_timer >= 1.0:
			_acquire_timer = 0.0
			_try_acquire_camera()
	if _running:
		_elapsed += delta
		if _max_mode:
			_extract()
		else:
			_since_extract += delta
			if _since_extract >= _extract_interval:
				_since_extract = fmod(_since_extract, _extract_interval)
				_extract()
		if _elapsed >= _run_limit_s:
			_stop_run()
	_sec_timer += delta
	if _sec_timer >= 1.0:
		_sec_timer = fmod(_sec_timer, 1.0)
		_sample_and_log()


# --- camera ---

func _try_acquire_camera() -> void:
	if OS.has_feature("android") \
			and not OS.get_granted_permissions().has("android.permission.CAMERA"):
		_status_msg = "waiting for CAMERA permission"
		return
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		_status_msg = "no camera feeds"
		return
	_cam_idx = clampi(_cam_idx, 0, feeds.size() - 1)
	_attach_feed(feeds[_cam_idx])


func _attach_feed(feed: CameraFeed) -> void:
	_detach_feed()
	_feed = feed
	if not _feed.frame_changed.is_connected(_on_frame_changed):
		_feed.frame_changed.connect(_on_frame_changed)
	_apply_resolution()
	_cam_texture.set_camera_feed_id(_feed.get_id())
	_cam_texture.camera_is_active = true
	_feed.set_active(true)
	print("feed active: '%s' position=%s" % [_feed.get_name(), _pos_name(_feed.get_position())])


func _detach_feed() -> void:
	if _feed != null:
		_feed.set_active(false)
		_feed = null


func _apply_resolution() -> void:
	var res: Vector2i = RES_PRESETS[_res_idx]
	# Pick the advertised format closest to the requested resolution.
	var formats: Array = _feed.get_formats()
	var best_idx := 0
	var best_dist := -1
	for i in formats.size():
		var w := int(formats[i].get("width", 0))
		var h := int(formats[i].get("height", 0))
		var dist: int = absi(w * h - res.x * res.y)
		if best_dist < 0 or dist < best_dist:
			best_dist = dist
			best_idx = i
	var ok := _feed.set_format(best_idx, {"width": res.x, "height": res.y})
	var fmt: Dictionary = _feed.get_format()
	print("set_format(%dx%d) idx=%d -> %s; actual: %s" % [res.x, res.y, best_idx, ok, fmt])


func _on_frame_changed() -> void:
	_feed_frames += 1


func _on_feed_added(_id: int) -> void:
	if _feed == null:
		_try_acquire_camera()


func _on_feed_removed(id: int) -> void:
	if _feed != null and _feed.get_id() == id:
		_detach_feed()


func _pos_name(pos: CameraFeed.FeedPosition) -> String:
	match pos:
		CameraFeed.FEED_FRONT:
			return "front"
		CameraFeed.FEED_BACK:
			return "back"
		_:
			return "unspecified"


# --- frame extraction: readback + encode, timed separately ---

func _extract() -> void:
	if _feed == null or not _feed.is_active():
		return
	var t0 := Time.get_ticks_usec()
	var img := _cam_texture.get_image()
	if img == null or img.is_empty():
		# Fallback readback path; on some backends CameraTexture.get_image() fails.
		img = RenderingServer.texture_2d_get(_cam_texture.get_rid())
		if img != null and not img.is_empty():
			_readback_path = "texture_2d_get"
	else:
		_readback_path = "get_image"
	var t1 := Time.get_ticks_usec()
	if img == null or img.is_empty():
		_errors += 1
		return
	var buf := img.save_jpg_to_buffer(JPEG_QUALITY)
	var t2 := Time.get_ticks_usec()
	var read_ms := (t1 - t0) / 1000.0
	var enc_ms := (t2 - t1) / 1000.0
	_read_ms.append(read_ms)
	_enc_ms.append(enc_ms)
	_sec_read.append(read_ms)
	_sec_enc.append(enc_ms)
	_sec_enc_kb.append(buf.size() / 1024.0)
	_extracted += 1


# --- per-second sampling and logging ---

func _sample_and_log() -> void:
	var render_fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var proc_cpu := _read_proc_cpu_pct()
	var total_cpu := _read_total_cpu_pct()
	var temp := _read_temp_c()
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var state := "IDLE"
	var w := 0
	var h := 0
	if _running:
		state = "RUN" if (_feed != null and _feed.is_active()) else "NO_FEED"
	if _feed != null and _feed.is_active():
		var fmt: Dictionary = _feed.get_format()
		w = int(fmt.get("width", 0))
		h = int(fmt.get("height", 0))
	var read_avg := _avg(_sec_read)
	var read_max := _max(_sec_read)
	var enc_avg := _avg(_sec_enc)
	var enc_max := _max(_sec_enc)
	var kb_avg := _avg(_sec_enc_kb)
	var target: float = RATE_PRESETS[_rate_idx]
	if _csv != null:
		_csv.store_line("%.1f,%s,%.0f,%d,%d,%.0f,%d,%d,%.2f,%.2f,%.2f,%.2f,%.1f,%.1f,%.1f,%.1f,%.1f,%d" % [
			_elapsed, state, render_fps, _feed_frames, _extracted, target, w, h,
			read_avg, read_max, enc_avg, enc_max, kb_avg,
			proc_cpu, total_cpu, mem_mb, temp, _errors])
		_csv.flush()
	_stats.text = (
		"state %s   elapsed %ds / %ds\n"
		+ "feed %s (%s) %dx%d @ %d fps\n"
		+ "extracted %d/s (target %s)   errors %d\n"
		+ "readback ms avg %.1f max %.1f   encode ms avg %.1f max %.1f   %.0f KB/frame\n"
		+ "cpu proc %.0f%% total %.0f%%   mem %.0f MB   temp %.1f C\n"
		+ "%s"
	) % [
		state, int(_elapsed), int(_run_limit_s),
		_feed.get_name() if _feed else _status_msg,
		_pos_name(_feed.get_position()) if _feed else "", w, h, _feed_frames,
		_extracted, ("MAX" if _max_mode else "%d fps" % int(target)), _errors,
		read_avg, read_max, enc_avg, enc_max, kb_avg,
		proc_cpu, total_cpu, mem_mb, temp,
		ProjectSettings.globalize_path(_csv_path) if _csv != null else "",
	]
	_feed_frames = 0
	_extracted = 0
	_sec_read.clear()
	_sec_enc.clear()
	_sec_enc_kb.clear()


# --- run control ---

func _start_run() -> void:
	if _running:
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_csv_path = "user://camera_spike_%s.csv" % stamp
	_csv = FileAccess.open(_csv_path, FileAccess.WRITE)
	if _csv == null:
		push_error("cannot open log file: " + _csv_path)
		return
	_csv.store_line(CSV_HEADER)
	_csv.flush()
	_read_ms.clear()
	_enc_ms.clear()
	_errors = 0
	_elapsed = 0.0
	_running = true
	_btn_start.text = "Stop"
	print("run started, logging to %s" % ProjectSettings.globalize_path(_csv_path))


func _stop_run() -> void:
	if not _running:
		return
	_running = false
	_btn_start.text = "Start"
	if _csv != null:
		_csv.close()
		_csv = null
	_write_summary()
	if _self_test:
		get_tree().quit()


func _write_summary() -> void:
	var summary := {
		"device": OS.get_model_name(),
		"os": OS.get_name(),
		"godot": Engine.get_version_info().get("string", ""),
		"readback_path": _readback_path,
		"duration_s": snappedf(_elapsed, 0.1),
		"feed": _feed.get_name() if _feed else "",
		"format": _feed.get_format() if _feed else {},
		"target_extract_fps": ("MAX" if _max_mode else RATE_PRESETS[_rate_idx]),
		"frames_extracted": _read_ms.size(),
		"errors": _errors,
		"readback_ms": _series_stats(_read_ms),
		"encode_ms": _series_stats(_enc_ms),
		"csv": ProjectSettings.globalize_path(_csv_path),
	}
	var path := _csv_path.replace(".csv", ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	print("SUMMARY " + JSON.stringify(summary))


# --- /proc and /sys readers (best-effort; -1 when unreadable) ---

func _read_proc_cpu_pct() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return -1.0
	# get_line(), not get_as_text(): procfs files report size 0, so
	# get_as_text() returns an empty string without reading anything.
	var text := f.get_line()
	var close := text.rfind(")")
	if close < 0:
		return -1.0
	# After the comm field: parts[0] = state (field 3), so utime (14) -> index 11.
	var parts := text.substr(close + 1).split(" ", false)
	if parts.size() <= 12:
		return -1.0
	var ticks := parts[11].to_int() + parts[12].to_int()
	var now := Time.get_ticks_msec() / 1000.0
	var pct := -1.0
	if _prev_proc_ticks >= 0 and now > _prev_proc_time:
		pct = (ticks - _prev_proc_ticks) / USER_HZ / (now - _prev_proc_time) * 100.0
	_prev_proc_ticks = ticks
	_prev_proc_time = now
	return pct


func _read_total_cpu_pct() -> float:
	var f := FileAccess.open("/proc/stat", FileAccess.READ)
	if f == null:
		return -1.0
	var line := f.get_line()
	if not line.begins_with("cpu"):
		return -1.0
	var p := line.split(" ", false)
	if p.size() < 8:
		return -1.0
	var total := 0
	for i in range(1, 8):
		total += p[i].to_int()
	var idle := p[4].to_int() + p[5].to_int()  # idle + iowait
	var pct := -1.0
	if _prev_cpu_total > 0 and total > _prev_cpu_total:
		var busy_delta := (total - idle) - (_prev_cpu_total - _prev_cpu_idle)
		pct = float(busy_delta) / float(total - _prev_cpu_total) * 100.0
	_prev_cpu_total = total
	_prev_cpu_idle = idle
	return pct


func _init_thermal() -> void:
	# App sandbox usually cannot read /sys/class/thermal on Android (SELinux);
	# the adb-side collector in tools/ covers thermal then. Readable on Linux.
	for i in range(20):
		var path := "/sys/class/thermal/thermal_zone%d/temp" % i
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				f.close()
				_temp_files.append(path)


func _read_temp_c() -> float:
	var best := -1.0
	for path in _temp_files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		# get_line(), not get_as_text(): sysfs files report PAGE_SIZE as their
		# size but return fewer bytes, which makes get_as_text() error out.
		var milli := f.get_line().strip_edges().to_float()
		f.close()
		if milli > 0.0:
			best = maxf(best, milli / 1000.0)
	return best


# --- stats helpers ---

func _avg(a: Array[float]) -> float:
	if a.is_empty():
		return -1.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


func _max(a: Array[float]) -> float:
	if a.is_empty():
		return -1.0
	var m := -INF
	for v in a:
		m = maxf(m, v)
	return m


func _series_stats(a: Array[float]) -> Dictionary:
	if a.is_empty():
		return {"count": 0}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var n := s.size()
	return {
		"count": n,
		"avg": snappedf(sum / n, 0.01),
		"p50": snappedf(s[int(0.50 * (n - 1))], 0.01),
		"p95": snappedf(s[int(0.95 * (n - 1))], 0.01),
		"max": snappedf(s[n - 1], 0.01),
	}


# --- UI ---

func _build_ui() -> void:
	_preview = TextureRect.new()
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_stats)
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	_btn_start = _make_button(hbox, "Start", _on_start_pressed)
	_btn_rate = _make_button(hbox, "", _on_rate_pressed)
	_btn_res = _make_button(hbox, "", _on_res_pressed)
	_btn_cam = _make_button(hbox, "", _on_cam_pressed)
	_update_button_labels()


func _make_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 80)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _update_button_labels() -> void:
	var r: float = RATE_PRESETS[_rate_idx]
	_btn_rate.text = "Rate: MAX" if r == 0.0 else "Rate: %d fps" % int(r)
	var res: Vector2i = RES_PRESETS[_res_idx]
	_btn_res.text = "Res: %dx%d" % [res.x, res.y]
	_btn_cam.text = "Camera: %d" % _cam_idx


func _on_start_pressed() -> void:
	if _running:
		_stop_run()
	else:
		_start_run()


func _on_rate_pressed() -> void:
	_rate_idx = (_rate_idx + 1) % RATE_PRESETS.size()
	var r: float = RATE_PRESETS[_rate_idx]
	_max_mode = r == 0.0
	_extract_interval = 1.0 / r if r > 0.0 else 0.0
	_update_button_labels()


func _on_res_pressed() -> void:
	_res_idx = (_res_idx + 1) % RES_PRESETS.size()
	if _feed != null:
		_feed.set_active(false)
		_apply_resolution()
		_feed.set_active(true)
	_update_button_labels()


func _on_cam_pressed() -> void:
	var feeds := CameraServer.feeds()
	if feeds.size() < 2:
		return
	_cam_idx = (_cam_idx + 1) % feeds.size()
	_attach_feed(feeds[_cam_idx])
	_update_button_labels()
