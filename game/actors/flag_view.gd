class_name FlagView
extends Node3D
## A team's flag in Capture the Flag, standing at its base or dropped on the
## floor. The flag a camper carries is drawn on the camper (CamperView).

const SCENE := "res://assets/kenney/prototype-kit/flag.glb"

var team := 0
var _flag: Node3D
var _glow: OmniLight3D


func setup(p_team: int) -> void:
	team = p_team
	_flag = (load(SCENE) as PackedScene).instantiate()
	_flag.scale = Vector3.ONE * 2.4
	add_child(_flag)
	tint(_flag, GameConfig.TEAM_COLORS[team])
	_glow = OmniLight3D.new()
	_glow.light_color = GameConfig.TEAM_COLORS[team]
	_glow.light_energy = 1.4
	_glow.omni_range = 3.5
	_glow.position.y = 1.2
	add_child(_glow)


## state 0 at base, 1 carried (hidden here), 2 dropped.
func apply(state: int, pos: Vector2) -> void:
	visible = state != 1
	position = Vector3(pos.x, 0.0, pos.y)
	_flag.rotation.z = 0.5 if state == 2 else 0.0


func _process(delta: float) -> void:
	_flag.rotation.y += delta * 0.8


## Recolours a Kenney model's materials (the flag cloth and pole).
static func tint(node: Node, color: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 0.25
			m.set_surface_override_material(s, mat)
