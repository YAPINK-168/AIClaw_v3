@tool
extends Node
class_name YouyouBlendshapeApplier
## 把柚柚 Eyes_*/Mouth_* 形态键写入已有角色网格，不替换骨架和蒙皮。
## 用法：挂到已有角色根节点 → 指定 youyou_blendshapes.bin → 勾选 apply_now → 保存场景。

const MAGIC := "YOUYBS01"
const MATCH_EPS := 0.0008
const ACCEPT_SCORE := 0.008
const MATCH_RATIO_MIN := 0.85

@export_file("*.bin") var blendshape_file: String = "res://youyou_assets/expressions_split/youyou_blendshapes.bin"
@export var character_root: NodePath
@export var apply_now: bool = false:
	set(value):
		apply_now = false
		if value:
			print(apply_blendshapes())

@export var reset_other_face_keys: bool = false

var last_report: String = ""
var last_diagnostics: Array = []
var last_success_count := 0
var last_total_count := 0


func apply_blendshapes() -> String:
	var result := apply_blendshapes_with_diagnostics()
	last_report = String(result.get("summary", ""))
	return last_report


func apply_blendshapes_with_diagnostics() -> Dictionary:
	last_diagnostics.clear()
	last_success_count = 0
	last_total_count = 0

	var root := _resolve_root()
	if root == null:
		var msg := "找不到角色根节点"
		last_report = msg
		return {"ok": false, "summary": msg, "diagnostics": [], "success_count": 0, "total_count": 0}

	var path := blendshape_file.strip_edges()
	if path.is_empty() or not FileAccess.file_exists(path):
		var msg := "找不到形态键文件：" + path
		last_report = msg
		return {"ok": false, "summary": msg, "diagnostics": [], "success_count": 0, "total_count": 0}

	var data := _load_bin(path)
	if data.is_empty():
		var msg := "形态键文件读取失败：" + path
		last_report = msg
		return {"ok": false, "summary": msg, "diagnostics": [], "success_count": 0, "total_count": 0}

	var instances := _collect_mesh_instances(root)
	if instances.is_empty():
		var msg := "角色下没有 MeshInstance3D"
		last_report = msg
		return {"ok": false, "summary": msg, "diagnostics": [], "success_count": 0, "total_count": 0}

	var used := {}
	var lines: PackedStringArray = PackedStringArray()
	for mesh_data in data:
		last_total_count += 1
		var entry := _diagnose_and_apply_mesh(instances, mesh_data, used)
		last_diagnostics.append(entry)
		if entry.get("passed", false):
			last_success_count += 1
		if entry.get("found", false):
			lines.append("%s -> %s | %s" % [entry["patch_name"], entry["node_name"], entry["result_message"]])
		else:
			lines.append("未匹配：%s（补丁顶点 %d）" % [entry["patch_name"], entry["patch_vertex_count"]])

	var all_ok := last_success_count == last_total_count and last_total_count > 0
	var summary := "写入完成 %d/%d\n%s" % [last_success_count, last_total_count, "\n".join(lines)]
	last_report = summary
	return {
		"ok": all_ok,
		"summary": summary,
		"diagnostics": last_diagnostics.duplicate(true),
		"success_count": last_success_count,
		"total_count": last_total_count,
		"bin_path": path,
	}


func get_last_diagnostics() -> Array:
	return last_diagnostics.duplicate(true)


func set_expression(emotion: String, value: float = 1.0) -> void:
	set_split_expression("Eyes_" + emotion, "Mouth_" + emotion, value)


func set_split_expression(eyes_key: String, mouth_key: String, value: float = 1.0) -> void:
	var root := _resolve_root()
	if root == null:
		return
	for mi in _collect_mesh_instances(root):
		if mi.mesh == null:
			continue
		if reset_other_face_keys:
			_zero_face_keys(mi)
		if _has_blendshape(mi, eyes_key):
			mi.set("blend_shapes/" + eyes_key, value)
		if _has_blendshape(mi, mouth_key):
			mi.set("blend_shapes/" + mouth_key, value)


func _diagnose_and_apply_mesh(instances: Array[MeshInstance3D], mesh_data: Dictionary, used: Dictionary) -> Dictionary:
	var entry := {
		"patch_name": String(mesh_data["name"]),
		"found": false,
		"node_name": "",
		"match_method": "none",
		"patch_vertex_count": int(mesh_data["vertex_count"]),
		"godot_surface_vertex_count": 0,
		"godot_unique_vertex_count": 0,
		"space_mode": "",
		"space_score": -1.0,
		"matched_vertices": 0,
		"total_vertices": 0,
		"match_ratio": 0.0,
		"avg_position_error": -1.0,
		"max_position_error": -1.0,
		"shapes_added": 0,
		"passed": false,
		"result_message": "",
		"failure_reason": "",
	}

	var mi := _find_mesh_instance(instances, mesh_data, used, entry)
	if mi == null:
		entry["failure_reason"] = "未找到对应 MeshInstance3D"
		entry["result_message"] = entry["failure_reason"]
		return entry

	entry["found"] = true
	entry["node_name"] = String(mi.name)
	used[mi] = true

	if not (mi.mesh is ArrayMesh):
		entry["failure_reason"] = "不是 ArrayMesh"
		entry["result_message"] = "跳过：" + entry["failure_reason"]
		return entry

	var original: ArrayMesh = mi.mesh
	entry["godot_surface_vertex_count"] = _surface_vertex_count(original)
	entry["godot_unique_vertex_count"] = _unique_vertex_count(original)

	var inject_result := _inject_into_mesh(mi, mesh_data, entry)
	entry.merge(inject_result, true)
	return entry


func _surface_vertex_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


func _resolve_root() -> Node:
	if not character_root.is_empty() and has_node(character_root):
		return get_node(character_root)
	return get_parent()


func _fail(message: String) -> String:
	last_report = message
	push_error(message)
	return message


func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_mesh_instances_recursive(root, result)
	return result


func _collect_mesh_instances_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances_recursive(child, result)


func _norm_name(value: String) -> String:
	return value.replace(".", "_").replace(" ", "_").to_lower()


func _find_mesh_instance(
	instances: Array[MeshInstance3D],
	mesh_data: Dictionary,
	used: Dictionary,
	entry: Dictionary
) -> MeshInstance3D:
	var target := String(mesh_data["name"])
	var target_norm := _norm_name(target)
	for mi in instances:
		if used.has(mi):
			continue
		if mi.name == target or _norm_name(mi.name) == target_norm:
			entry["match_method"] = "name"
			return mi
	var want_count := int(mesh_data["vertex_count"])
	var best: MeshInstance3D = null
	var best_diff := 999999
	for mi in instances:
		if used.has(mi) or not (mi.mesh is ArrayMesh):
			continue
		var unique_count := _unique_vertex_count(mi.mesh)
		var diff: int = abs(unique_count - want_count)
		if diff < best_diff and diff <= max(2, int(want_count / 50)):
			best_diff = diff
			best = mi
	if best != null:
		entry["match_method"] = "vertex_count"
	return best


func _unique_vertex_count(mesh: ArrayMesh) -> int:
	var seen := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			seen[_quant_key(v, 8000.0)] = true
	return seen.size()


func _inject_into_mesh(mi: MeshInstance3D, mesh_data: Dictionary, entry: Dictionary) -> Dictionary:
	var out := {
		"passed": false,
		"shapes_added": 0,
		"result_message": "",
		"failure_reason": "",
	}

	var original: ArrayMesh = mi.mesh
	if original.get_surface_count() == 0:
		out["failure_reason"] = "没有 surface"
		out["result_message"] = "跳过：" + out["failure_reason"]
		return out

	var src_basis: PackedVector3Array = mesh_data["basis"]
	var src_shapes: Dictionary = mesh_data["shapes"]
	var new_names: Array = src_shapes.keys()
	if new_names.is_empty():
		out["failure_reason"] = "补丁无形态键"
		out["result_message"] = out["failure_reason"]
		return out

	if _has_blendshape(mi, String(new_names[0])) and _has_blendshape(mi, String(new_names[new_names.size() - 1])):
		out["shapes_added"] = 0
		out["passed"] = true
		out["space_mode"] = "skipped_existing"
		out["result_message"] = "已有形态键，跳过重复写入"
		entry["space_mode"] = "skipped_existing"
		entry["matched_vertices"] = entry.get("godot_surface_vertex_count", 0)
		entry["total_vertices"] = entry.get("godot_surface_vertex_count", 0)
		entry["match_ratio"] = 1.0
		return out

	var space := _pick_space_for_instance(mi, original, src_basis, mesh_data["xform"])
	if space.is_empty():
		out["failure_reason"] = "顶点和现有模型对不上（坐标/压缩）"
		out["result_message"] = "失败：" + out["failure_reason"]
		entry["space_mode"] = ""
		return out

	var converted_basis: PackedVector3Array = space["basis"]
	var mode: String = space["mode"]
	var xform: Transform3D = space["xform"]
	entry["space_mode"] = mode
	entry["space_score"] = float(space["score"])

	var mapping_stats := _mapping_stats_for_mesh(original, converted_basis)
	entry["matched_vertices"] = int(mapping_stats["matched"])
	entry["total_vertices"] = int(mapping_stats["total"])
	entry["match_ratio"] = float(mapping_stats["ratio"])
	entry["avg_position_error"] = float(mapping_stats["avg_error"])
	entry["max_position_error"] = float(mapping_stats["max_error"])

	var existing_names: PackedStringArray = PackedStringArray()
	for i in original.get_blend_shape_count():
		existing_names.append(String(original.get_blend_shape_name(i)))

	var all_names: PackedStringArray = existing_names.duplicate()
	for shape_name in new_names:
		if existing_names.find(shape_name) == -1:
			all_names.append(String(shape_name))
	out["shapes_added"] = all_names.size() - existing_names.size()

	var new_mesh := ArrayMesh.new()
	new_mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	if original.get_blend_shape_count() > 0:
		new_mesh.blend_shape_mode = original.blend_shape_mode
	for shape_name in all_names:
		new_mesh.add_blend_shape(shape_name)
	new_mesh.custom_aabb = original.custom_aabb

	var use_normalized := new_mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for surface in original.get_surface_count():
		var arrays := original.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mapping := _map_vertices(verts, converted_basis)
		var old_blend := original.surface_get_blend_shape_arrays(surface)
		var blend_arrays: Array = []
		for shape_name in all_names:
			var existing_index := existing_names.find(shape_name)
			if existing_index >= 0 and existing_index < old_blend.size():
				var copied: Array = (old_blend[existing_index] as Array).duplicate(true)
				blend_arrays.append(_complete_blend_item(arrays, copied, use_normalized))
				continue
			var src_delta: PackedVector3Array = src_shapes[shape_name]
			var dst_delta := PackedVector3Array()
			dst_delta.resize(verts.size())
			var index_map: PackedInt32Array = mapping["indices"]
			for i in verts.size():
				dst_delta[i] = _transform_delta(src_delta[index_map[i]], mode, xform)
			var blend_item: Array = []
			blend_item.resize(Mesh.ARRAY_MAX)
			if use_normalized:
				var absolute := PackedVector3Array()
				absolute.resize(verts.size())
				for i in verts.size():
					absolute[i] = verts[i] + dst_delta[i]
				blend_item[Mesh.ARRAY_VERTEX] = absolute
			else:
				blend_item[Mesh.ARRAY_VERTEX] = dst_delta
			blend_arrays.append(_complete_blend_item(arrays, blend_item, use_normalized))
		var surface_before := new_mesh.get_surface_count()
		new_mesh.add_surface_from_arrays(
			original.surface_get_primitive_type(surface),
			arrays,
			blend_arrays,
			{},
			original.surface_get_format(surface)
		)
		if new_mesh.get_surface_count() <= surface_before:
			out["failure_reason"] = "surface %d 重建失败（BlendShape 与主网格格式不一致）" % surface
			out["result_message"] = "失败：" + out["failure_reason"]
			return out
		new_mesh.surface_set_material(surface, original.surface_get_material(surface))
		new_mesh.surface_set_name(surface, original.surface_get_name(surface))

	if new_mesh.get_surface_count() != original.get_surface_count():
		out["failure_reason"] = "surface 数量不匹配 %d/%d" % [
			new_mesh.get_surface_count(), original.get_surface_count()
		]
		out["result_message"] = "失败：" + out["failure_reason"]
		return out

	if entry["total_vertices"] == 0 or entry["match_ratio"] < MATCH_RATIO_MIN:
		out["failure_reason"] = "顶点匹配率 %.1f%% 低于阈值 %.0f%%" % [
			entry["match_ratio"] * 100.0, MATCH_RATIO_MIN * 100.0
		]
		out["result_message"] = "失败：" + out["failure_reason"]
		return out

	mi.mesh = new_mesh
	out["passed"] = true
	out["result_message"] = "OK 匹配率 %.1f%% 空间 %s 新增形态键 %d" % [
		entry["match_ratio"] * 100.0, mode, out["shapes_added"]
	]
	return out


func _complete_blend_item(base_arrays: Array, blend_item: Array, use_normalized: bool) -> Array:
	var out: Array = blend_item.duplicate(true)
	if out.size() < Mesh.ARRAY_MAX:
		out.resize(Mesh.ARRAY_MAX)
	var vert_count := (base_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if base_arrays[Mesh.ARRAY_NORMAL] != null:
		var need_fill := out[Mesh.ARRAY_NORMAL] == null
		if not need_fill:
			var existing: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
			need_fill = existing.size() != vert_count
		if need_fill:
			var base_norm: PackedVector3Array = base_arrays[Mesh.ARRAY_NORMAL]
			var bn := PackedVector3Array()
			bn.resize(vert_count)
			for i in vert_count:
				bn[i] = base_norm[i] if use_normalized else Vector3.ZERO
			out[Mesh.ARRAY_NORMAL] = bn
	if base_arrays[Mesh.ARRAY_TANGENT] != null:
		var need_fill_t := out[Mesh.ARRAY_TANGENT] == null
		var base_tan: PackedFloat32Array = base_arrays[Mesh.ARRAY_TANGENT]
		if not need_fill_t:
			var existing_t: PackedFloat32Array = out[Mesh.ARRAY_TANGENT]
			need_fill_t = existing_t.size() != base_tan.size()
		if need_fill_t:
			var bt := PackedFloat32Array()
			bt.resize(base_tan.size())
			for i in base_tan.size():
				bt[i] = base_tan[i] if use_normalized else 0.0
			out[Mesh.ARRAY_TANGENT] = bt
	return out


func _mapping_stats_for_mesh(original: ArrayMesh, converted_basis: PackedVector3Array) -> Dictionary:
	var matched_total := 0
	var vertex_total := 0
	var dist_sum := 0.0
	var dist_max := 0.0
	for surface in original.get_surface_count():
		var arrays := original.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mapping := _map_vertices(verts, converted_basis)
		matched_total += int(mapping["matched"])
		vertex_total += verts.size()
		var stats: Dictionary = mapping["distance_stats"]
		dist_sum += float(stats["sum"])
		dist_max = maxf(dist_max, float(stats["max"]))
	var ratio := 0.0
	var avg := 0.0
	if vertex_total > 0:
		ratio = float(matched_total) / float(vertex_total)
		avg = dist_sum / float(vertex_total)
	return {
		"matched": matched_total,
		"total": vertex_total,
		"ratio": ratio,
		"avg_error": avg,
		"max_error": dist_max,
	}


func _pick_space_for_instance(
	mi: MeshInstance3D,
	original: ArrayMesh,
	src_basis: PackedVector3Array,
	bin_xform: Transform3D
) -> Dictionary:
	var candidates: Array[Transform3D] = [bin_xform, mi.global_transform, mi.global_transform * bin_xform]
	var best: Dictionary = {}
	var best_ratio := -1.0
	var best_score := INF
	for xf in candidates:
		var space := _pick_space_by_mapping(original, src_basis, xf)
		if space.is_empty():
			continue
		var ratio: float = float(space["match_ratio"])
		var score: float = float(space["score"])
		if ratio > best_ratio or (is_equal_approx(ratio, best_ratio) and score < best_score):
			best_ratio = ratio
			best_score = score
			best = space
	return best


func _pick_space_by_mapping(original: ArrayMesh, src_basis: PackedVector3Array, xform: Transform3D) -> Dictionary:
	var modes := PackedStringArray(["local", "local_yup", "world", "world_yup"])
	var best_mode := ""
	var best_score := INF
	var best_basis := PackedVector3Array()
	var best_ratio := -1.0
	for mode in modes:
		var converted := _transform_basis(src_basis, mode, xform)
		var score := _basis_score(original, converted)
		var stats := _mapping_stats_for_mesh(original, converted)
		var ratio: float = float(stats["ratio"])
		if ratio > best_ratio or (is_equal_approx(ratio, best_ratio) and score < best_score):
			best_ratio = ratio
			best_score = score
			best_mode = mode
			best_basis = converted
	if best_ratio < MATCH_RATIO_MIN:
		return {}
	if best_score > ACCEPT_SCORE and best_ratio < 0.98:
		return {}
	return {
		"mode": best_mode,
		"basis": best_basis,
		"xform": xform,
		"score": best_score,
		"match_ratio": best_ratio,
	}


func _transform_basis(src_basis: PackedVector3Array, mode: String, xform: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(src_basis.size())
	for i in src_basis.size():
		out[i] = _transform_pos(src_basis[i], mode, xform)
	return out


func _transform_pos(point: Vector3, mode: String, xform: Transform3D) -> Vector3:
	match mode:
		"local_yup":
			return Vector3(point.x, point.z, -point.y)
		"world":
			return xform * point
		"world_yup":
			var world := xform * point
			return Vector3(world.x, world.z, -world.y)
		_:
			return point


func _transform_delta(delta: Vector3, mode: String, xform: Transform3D) -> Vector3:
	match mode:
		"local_yup":
			return Vector3(delta.x, delta.z, -delta.y)
		"world":
			return xform.basis * delta
		"world_yup":
			var world := xform.basis * delta
			return Vector3(world.x, world.z, -world.y)
		_:
			return delta


func _basis_score(original: ArrayMesh, src_basis: PackedVector3Array) -> float:
	var lookup := _build_lookup(src_basis)
	var sample := 0
	var dist_sum := 0.0
	for surface in original.get_surface_count():
		var arrays := original.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var step: int = max(1, int(verts.size() / 80))
		var i := 0
		while i < verts.size():
			var nearest := _nearest_index(verts[i], src_basis, lookup)
			dist_sum += verts[i].distance_to(src_basis[nearest])
			sample += 1
			i += step
	if sample == 0:
		return 999.0
	return dist_sum / float(sample)


func _map_vertices(dst_verts: PackedVector3Array, src_basis: PackedVector3Array) -> Dictionary:
	var lookup := _build_lookup(src_basis)
	var indices := PackedInt32Array()
	indices.resize(dst_verts.size())
	var matched := 0
	var dist_sum := 0.0
	var dist_max := 0.0
	for i in dst_verts.size():
		var idx := _nearest_index(dst_verts[i], src_basis, lookup)
		indices[i] = idx
		var dist := dst_verts[i].distance_to(src_basis[idx])
		dist_sum += dist
		dist_max = maxf(dist_max, dist)
		if dist <= MATCH_EPS:
			matched += 1
	return {
		"indices": indices,
		"matched": matched,
		"distance_stats": {"sum": dist_sum, "max": dist_max},
	}


func _build_lookup(src_basis: PackedVector3Array) -> Dictionary:
	var lookup := {}
	for i in src_basis.size():
		var key := _quant_key(src_basis[i], 2000.0)
		if not lookup.has(key):
			lookup[key] = PackedInt32Array()
		var bucket: PackedInt32Array = lookup[key]
		bucket.append(i)
		lookup[key] = bucket
	return lookup


func _nearest_index(point: Vector3, src_basis: PackedVector3Array, lookup: Dictionary) -> int:
	var center := _quant_key(point, 2000.0)
	var best_idx := 0
	var best_dist := INF
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var key := center + Vector3i(x, y, z)
				if not lookup.has(key):
					continue
				var bucket: PackedInt32Array = lookup[key]
				for idx in bucket:
					var dist := point.distance_squared_to(src_basis[idx])
					if dist < best_dist:
						best_dist = dist
						best_idx = idx
	if best_dist < INF:
		return best_idx
	for i in src_basis.size():
		var dist := point.distance_squared_to(src_basis[i])
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx


func _quant_key(v: Vector3, scale: float) -> Vector3i:
	return Vector3i(roundi(v.x * scale), roundi(v.y * scale), roundi(v.z * scale))


func _has_blendshape(mi: MeshInstance3D, shape_name: String) -> bool:
	if not (mi.mesh is ArrayMesh):
		return false
	var mesh: ArrayMesh = mi.mesh
	for i in mesh.get_blend_shape_count():
		if String(mesh.get_blend_shape_name(i)) == shape_name:
			return true
	return false


func _zero_face_keys(mi: MeshInstance3D) -> void:
	if not (mi.mesh is ArrayMesh):
		return
	var mesh: ArrayMesh = mi.mesh
	for i in mesh.get_blend_shape_count():
		var shape_name := String(mesh.get_blend_shape_name(i))
		if shape_name.begins_with("Eyes_") or shape_name.begins_with("Mouth_"):
			mi.set("blend_shapes/" + shape_name, 0.0)


func _load_bin(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var magic := file.get_buffer(8).get_string_from_ascii()
	if magic != MAGIC:
		push_error("形态键文件头不正确：" + magic)
		return []
	var version := file.get_32()
	var mesh_count := file.get_32()
	if version != 1:
		push_error("不支持的形态键版本：" + str(version))
		return []
	var meshes: Array = []
	for _mesh_i in mesh_count:
		var mesh_name := _read_string(file)
		var vertex_count := file.get_32()
		var shape_count := file.get_32()
		var x_axis := Vector3(file.get_float(), file.get_float(), file.get_float())
		var y_axis := Vector3(file.get_float(), file.get_float(), file.get_float())
		var z_axis := Vector3(file.get_float(), file.get_float(), file.get_float())
		var origin := Vector3(file.get_float(), file.get_float(), file.get_float())
		var xform := Transform3D(Basis(x_axis, y_axis, z_axis), origin)
		var basis := PackedVector3Array()
		basis.resize(vertex_count)
		for i in vertex_count:
			basis[i] = Vector3(file.get_float(), file.get_float(), file.get_float())
		var shapes := {}
		for _shape_i in shape_count:
			var shape_name := _read_string(file)
			var deltas := PackedVector3Array()
			deltas.resize(vertex_count)
			for i in vertex_count:
				deltas[i] = Vector3(file.get_float(), file.get_float(), file.get_float())
			shapes[shape_name] = deltas
		meshes.append({
			"name": mesh_name,
			"vertex_count": vertex_count,
			"xform": xform,
			"basis": basis,
			"shapes": shapes,
		})
	return meshes


func _read_string(file: FileAccess) -> String:
	var size := file.get_32()
	return file.get_buffer(size).get_string_from_utf8()
