extends Node2D
## 加长水层：贴图海面行对齐 LAYER_SURFACE_Y；shader 裁 y>=398 露沙。

const TEX_WATER_LONG := "res://miner/assets/tide/water_sky_tide_layer.png"
const TEX_WATER_FALLBACK := preload("res://miner/assets/tide/water_layer.jpg")
const WATER_LAYER_SHADER := preload("res://miner/shaders/water_layer.gdshader")
const WATER_BOTTOM_Y := 375.0
const SALVAGE_CLEAR_Y := 398.0
## 豆包 1600 高水层：海面在贴图 796/1600
const SURFACE_TEX_RATIO_LONG := 0.4975
const SURFACE_TEX_RATIO_FALLBACK := 235.0 / 960.0
## 负值把海面抬高。-42 对齐到船底那条水面
@export var surface_align_offset_y: float = -42.0

var _sprite: Sprite2D
var _world_w: float = 1280.0
var _surface_y: float = 176.0
var _tex_scale: float = 1.0
var _tex_h: float = 960.0
var _half_display_h: float = 360.0


func setup(p_surface_y: float, p_world_w: float) -> void:
	z_as_relative = true
	z_index = -1
	_surface_y = p_surface_y
	_world_w = maxf(p_world_w, 128.0)
	_ensure_sprite()


func set_world_width(_p_world_w: float) -> void:
	_world_w = maxf(_p_world_w, 128.0)
	_apply_sprite_pos()


func fit_like_background(world_w: float, _design_h: float, tex_scale: float) -> void:
	_ensure_sprite()
	_world_w = maxf(world_w, 128.0)
	_tex_scale = tex_scale
	_tex_h = _sprite.texture.get_height()
	_half_display_h = _tex_scale * _tex_h * 0.5
	_apply_shader_uniforms()
	_apply_sprite_pos()


func set_tide_scroll(_tide_layer_y: float) -> void:
	pass


func set_blood(amount: float) -> void:
	if _sprite == null or not (_sprite.material is ShaderMaterial):
		return
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("surface_uv_y", _surface_tex_ratio())
	mat.set_shader_parameter("blood", clampf(amount, 0.0, 1.0))


func _surface_tex_ratio() -> float:
	if _tex_h > 1000.0:
		return SURFACE_TEX_RATIO_LONG
	return SURFACE_TEX_RATIO_FALLBACK


func _apply_sprite_pos() -> void:
	if _sprite == null:
		return
	var surface_tex_y := _tex_h * _surface_tex_ratio()
	var cy := _surface_y - surface_tex_y * _tex_scale + _half_display_h + surface_align_offset_y
	_sprite.position = Vector2(_world_w * 0.5, cy)


func _apply_shader_uniforms() -> void:
	if _sprite == null or not (_sprite.material is ShaderMaterial):
		return
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("water_bottom_y", WATER_BOTTOM_Y)
	mat.set_shader_parameter("salvage_clear_y", SALVAGE_CLEAR_Y)
	mat.set_shader_parameter("surface_uv_y", _surface_tex_ratio())


func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "WaterSprite"
	_sprite.texture = _load_water_texture()
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.z_index = 0
	var mat := ShaderMaterial.new()
	mat.shader = WATER_LAYER_SHADER
	_sprite.material = mat
	add_child(_sprite)
	_tex_h = _sprite.texture.get_height()


func _load_water_texture() -> Texture2D:
	if ResourceLoader.exists(TEX_WATER_LONG):
		return load(TEX_WATER_LONG) as Texture2D
	return TEX_WATER_FALLBACK
