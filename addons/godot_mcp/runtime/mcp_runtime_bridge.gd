extends Node
## MCP runtime bridge — runs INSIDE the played game, connects back to the editor.
##
## Injected as an autoload only when `game_run play {bridge:true}` is used. It
## reads the editor's bridge port from the user command line
## (`-- --mcp-bridge-port=N`), opens a TCP connection to 127.0.0.1:N, and serves
## newline-delimited JSON commands so the MCP server can inspect and drive the
## live game (scene tree, properties, eval, input synthesis, screenshots).
##
## Protocol (one JSON object per line):
##   editor -> game : {"id": <int>, "cmd": "<name>", "args": { ... }}
##   game -> editor : {"id": <int>, "ok": true,  "result": { ... }}
##                    {"id": <int>, "ok": false, "error": "<message>"}
##
## Pure GDScript on purpose: the played game must not depend on the C++
## GDExtension being enabled in the user's project.

var _peer: StreamPeerTCP = null
var _rx: String = ""
var _connected := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var port := _parse_port()
	if port <= 0:
		# Not launched with a bridge port — nothing to do.
		queue_free()
		return
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host("127.0.0.1", port)
	if err != OK:
		push_warning("[mcp-bridge] connect_to_host failed: %s" % err)
		queue_free()
		return

func _parse_port() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mcp-bridge-port="):
			return int(arg.substr("--mcp-bridge-port=".length()))
	return -1

func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not _connected:
			_connected = true
			_send({"id": 0, "cmd": "hello", "event": "connected",
				"result": {"scene": _scene_path()}})
		var available := _peer.get_available_bytes()
		if available > 0:
			var chunk := _peer.get_data(available)
			if chunk[0] == OK:
				var bytes: PackedByteArray = chunk[1]
				_rx += bytes.get_string_from_utf8()
				_drain_lines()
	elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		if _connected:
			# Editor went away; the game keeps running normally.
			_peer = null

func _drain_lines() -> void:
	while true:
		var nl := _rx.find("\n")
		if nl == -1:
			return
		var line := _rx.substr(0, nl).strip_edges()
		_rx = _rx.substr(nl + 1)
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_handle(parsed)

func _handle(req: Dictionary) -> void:
	var id := int(req.get("id", 0))
	var cmd := String(req.get("cmd", ""))
	var args: Dictionary = req.get("args", {})
	var out := {"id": id, "ok": true}
	var res = null
	var err := ""
	match cmd:
		"ping":
			res = {"pong": true}
		"get_scene_tree":
			res = _get_scene_tree(args)
		"get_node_info":
			var n := _resolve(args.get("path", ""))
			if n == null: err = "Node not found: %s" % args.get("path", "")
			else: res = _node_info(n, true)
		"get_property":
			var n2 := _resolve(args.get("path", ""))
			if n2 == null: err = "Node not found"
			else: res = {"value": _ser(n2.get(String(args.get("property", ""))))}
		"find_nodes":
			res = _find_nodes(args)
		"get_performance":
			res = _performance()
		"set_property":
			var n3 := _resolve(args.get("path", ""))
			if n3 == null: err = "Node not found"
			else:
				n3.set(String(args.get("property", "")), _deser(args.get("value")))
				res = {"ok": true}
		"call_method":
			var n4 := _resolve(args.get("path", ""))
			if n4 == null: err = "Node not found"
			else:
				var margs: Array = args.get("args", [])
				res = {"return": _ser(n4.callv(String(args.get("method", "")), margs))}
		"eval":
			var ev := _eval(args)
			if ev.has("error"): err = ev["error"]
			else: res = ev
		"emit_signal":
			var n5 := _resolve(args.get("path", ""))
			if n5 == null: err = "Node not found"
			else:
				var sargs: Array = args.get("args", [])
				n5.emit_signal.callv([String(args.get("signal", ""))] + sargs)
				res = {"ok": true}
		"pause":
			get_tree().paused = true
			res = {"paused": true}
		"resume":
			get_tree().paused = false
			res = {"paused": false}
		"quit":
			res = {"quitting": true}
			_send({"id": id, "ok": true, "result": res})
			get_tree().quit()
			return
		"action_press":
			Input.action_press(String(args.get("action", "")), float(args.get("strength", 1.0)))
			res = {"ok": true}
		"action_release":
			Input.action_release(String(args.get("action", "")))
			res = {"ok": true}
		"key":
			_synth_key(args)
			res = {"ok": true}
		"mouse_click":
			_synth_mouse_click(args)
			res = {"ok": true}
		"mouse_move":
			_synth_mouse_move(args)
			res = {"ok": true}
		"type_text":
			_synth_text(String(args.get("text", "")))
			res = {"ok": true}
		"screenshot":
			var sh := _screenshot(args)
			if sh.has("error"): err = sh["error"]
			else: res = sh
		_:
			err = "Unknown cmd: %s" % cmd

	if err != "":
		out["ok"] = false
		out["error"] = err
	else:
		out["result"] = res
	_send(out)

# ---------- inspection ----------

func _scene_path() -> String:
	var cur := get_tree().current_scene
	return cur.scene_file_path if cur else ""

func _resolve(path) -> Node:
	var p := String(path)
	if p.is_empty() or p == "/root":
		return get_tree().root
	if p == "current" or p == ".":
		return get_tree().current_scene
	var n := get_node_or_null(p)
	if n: return n
	# Try relative to current scene.
	var cur := get_tree().current_scene
	if cur:
		if cur.name == p: return cur
		n = cur.get_node_or_null(p)
		if n: return n
		n = cur.find_child(p, true, false)
		if n: return n
	return null

func _get_scene_tree(args: Dictionary) -> Dictionary:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	var max_depth := int(args.get("max_depth", 6))
	var counter := {"n": 0, "cap": int(args.get("max_nodes", 300))}
	return {"root": _tree_node(root, max_depth, counter), "truncated": counter["n"] >= counter["cap"]}

func _tree_node(node: Node, depth: int, counter: Dictionary) -> Dictionary:
	counter["n"] += 1
	var d := {"name": node.name, "type": node.get_class(),
		"path": String(node.get_path())}
	if node is CanvasItem:
		d["visible"] = node.visible
	if depth > 0 and counter["n"] < counter["cap"]:
		var kids := []
		for c in node.get_children():
			if counter["n"] >= counter["cap"]:
				break
			kids.append(_tree_node(c, depth - 1, counter))
		if not kids.is_empty():
			d["children"] = kids
	return d

func _node_info(node: Node, include_props: bool) -> Dictionary:
	var d := {"name": node.name, "type": node.get_class(),
		"path": String(node.get_path()),
		"child_count": node.get_child_count()}
	var scr = node.get_script()
	if scr: d["script"] = scr.resource_path
	if node is CanvasItem: d["visible"] = node.visible
	if node is Node2D:
		d["position"] = _ser(node.position)
		d["rotation"] = node.rotation
	if include_props:
		var props := {}
		for pi in node.get_property_list():
			if pi["usage"] & PROPERTY_USAGE_EDITOR and pi["usage"] & PROPERTY_USAGE_STORAGE:
				var pname: String = pi["name"]
				if pname.contains("/"):
					continue
				props[pname] = _ser(node.get(pname))
		d["properties"] = props
	return d

func _find_nodes(args: Dictionary) -> Dictionary:
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var by_name := String(args.get("name", ""))
	var by_type := String(args.get("type", ""))
	var found := []
	var cap := int(args.get("max", 100))
	_find_rec(root, by_name, by_type, found, cap)
	return {"count": found.size(), "nodes": found}

func _find_rec(node: Node, by_name: String, by_type: String, out: Array, cap: int) -> void:
	if out.size() >= cap:
		return
	var ok := true
	if not by_name.is_empty() and not String(node.name).match(by_name) and not String(node.name).contains(by_name):
		ok = false
	if not by_type.is_empty() and not node.is_class(by_type):
		ok = false
	if ok:
		out.append({"name": node.name, "type": node.get_class(), "path": String(node.get_path())})
	for c in node.get_children():
		_find_rec(c, by_name, by_type, out, cap)

func _performance() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_time_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	}

# ---------- control ----------

func _eval(args: Dictionary) -> Dictionary:
	var expr_text := String(args.get("expression", ""))
	if expr_text.is_empty():
		return {"error": "expression required"}
	var expr := Expression.new()
	# Optional named inputs: {"self": <node path>} bound as `target`.
	var input_names := PackedStringArray(["tree", "root"])
	var inputs := [get_tree(), get_tree().root]
	var target = null
	if args.has("path"):
		target = _resolve(args.get("path"))
		input_names.append("target")
		inputs.append(target)
	var perr := expr.parse(expr_text, input_names)
	if perr != OK:
		return {"error": "parse error: %s" % expr.get_error_text()}
	var base = target if target != null else self
	var value = expr.execute(inputs, base, true)
	if expr.has_execute_failed():
		return {"error": "execute failed: %s" % expr.get_error_text()}
	return {"value": _ser(value)}

# ---------- input synthesis ----------

func _synth_key(args: Dictionary) -> void:
	var ev := InputEventKey.new()
	ev.keycode = int(args.get("keycode", 0))
	ev.physical_keycode = ev.keycode
	ev.pressed = bool(args.get("pressed", true))
	Input.parse_input_event(ev)

func _synth_mouse_click(args: Dictionary) -> void:
	var pos := Vector2(float(args.get("x", 0)), float(args.get("y", 0)))
	var button := int(args.get("button", MOUSE_BUTTON_LEFT))
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)

func _synth_mouse_move(args: Dictionary) -> void:
	var pos := Vector2(float(args.get("x", 0)), float(args.get("y", 0)))
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	Input.warp_mouse(pos)

func _synth_text(text: String) -> void:
	for i in text.length():
		var ev := InputEventKey.new()
		ev.unicode = text.unicode_at(i)
		ev.pressed = true
		Input.parse_input_event(ev)

# ---------- capture ----------

func _screenshot(args: Dictionary) -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {"error": "no viewport"}
	var img := vp.get_texture().get_image()
	if img == null:
		return {"error": "could not read viewport image"}
	var max_size := int(args.get("max_size", 800))
	var w := img.get_width()
	var h := img.get_height()
	if max_size > 0 and (w > max_size or h > max_size):
		var scale: float = float(max_size) / float(max(w, h))
		img.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_BILINEAR)
	var png := img.save_png_to_buffer()
	return {
		"width": img.get_width(),
		"height": img.get_height(),
		"png_base64": Marshalls.raw_to_base64(png),
	}

# ---------- (de)serialization ----------

func _ser(v):
	match typeof(v):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {"x": v.x, "y": v.y}
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return {"x": v.x, "y": v.y, "z": v.z}
		TYPE_COLOR:
			return {"r": v.r, "g": v.g, "b": v.b, "a": v.a}
		TYPE_OBJECT:
			if v == null:
				return null
			if v is Node:
				return {"__node": String(v.get_path())}
			if v is Resource:
				return {"__resource": v.resource_path}
			return str(v)
		TYPE_NIL:
			return null
		TYPE_ARRAY:
			var out := []
			for e in v:
				out.append(_ser(e))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[String(k)] = _ser(v[k])
			return d
		_:
			return v

func _deser(v):
	if typeof(v) == TYPE_DICTIONARY:
		if v.has("x") and v.has("y") and v.has("z"):
			return Vector3(v["x"], v["y"], v["z"])
		if v.has("x") and v.has("y"):
			return Vector2(v["x"], v["y"])
		if v.has("r") and v.has("g") and v.has("b"):
			return Color(v["r"], v["g"], v["b"], v.get("a", 1.0))
	return v

# ---------- transport ----------

func _send(obj: Dictionary) -> void:
	if _peer == null:
		return
	var line := JSON.stringify(obj) + "\n"
	_peer.put_data(line.to_utf8_buffer())
