class_name ShipMaterials
## Shared, cached materials for ship construction. Anything that needs to
## change at runtime (lights, screens) creates its own instance instead.

const HULL_SHADER := preload("res://shaders/hull_panel.gdshader")
const HAZARD_SHADER := preload("res://shaders/hazard.gdshader")

static var _cache := {}


## Procedural plating. `panel` is the plate size in metres.
static func hull(color: Color, panel := Vector2(1.0, 1.0), wear := 0.5, metallic := 0.55,
		roughness := 0.55, rivets := 1.0) -> ShaderMaterial:
	var key := "hull|%s|%s|%.2f|%.2f|%.2f|%.1f" % [color.to_html(), panel, wear, metallic, roughness, rivets]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = HULL_SHADER
	m.set_shader_parameter(&"base_color", color)
	m.set_shader_parameter(&"panel_size", panel)
	m.set_shader_parameter(&"wear", wear)
	m.set_shader_parameter(&"metallic", metallic)
	m.set_shader_parameter(&"roughness", roughness)
	m.set_shader_parameter(&"rivets", rivets)
	_cache[key] = m
	return m


static func hazard() -> ShaderMaterial:
	if _cache.has("hazard"):
		return _cache["hazard"]
	var m := ShaderMaterial.new()
	m.shader = HAZARD_SHADER
	_cache["hazard"] = m
	return m


static func metal(color: Color, roughness := 0.45, metallic := 0.85) -> StandardMaterial3D:
	return _standard("metal", color, roughness, metallic)


static func paint(color: Color, roughness := 0.7) -> StandardMaterial3D:
	return _standard("paint", color, roughness, 0.15)


static func rubber(color := Color(0.05, 0.05, 0.055)) -> StandardMaterial3D:
	return _standard("rubber", color, 0.95, 0.0)


## A new (uncached) emissive material, for things that glow or change.
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _standard(kind: String, color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%.2f" % [kind, color.to_html(), roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m
