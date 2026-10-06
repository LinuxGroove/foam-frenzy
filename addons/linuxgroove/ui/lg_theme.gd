class_name LGTheme
extends RefCounted
## Builds the shared Godot Theme from Kenney's "UI Pack - Adventure" textures
## and Kenney fonts (all CC0). Call [method apply] once at startup.
##
## Focus is drawn as a thick, bright outline so menus are easy to follow from
## the couch with a controller.

const TEX := "res://addons/linuxgroove/ui/textures/"
const FONTS := "res://addons/linuxgroove/ui/fonts/"

const INK := Color("3b2a1e")
const PARCHMENT := Color("fdf1d6")
const FOCUS := Color("ffd54a")
const DANGER := Color("e8635a")

static var heading_font: Font
static var body_font: Font
static var mono_font: Font


static func apply(root: Window, base_size := 22) -> Theme:
	var theme := build(base_size)
	root.theme = theme
	# Themes only pass down through Controls and Windows, so menus under a
	# CanvasLayer or a 3D scene wouldn't see it. Merging into the default
	# theme makes it apply everywhere.
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.get_default_theme().default_font_size = theme.default_font_size
	return theme


static func build(base_size := 22) -> Theme:
	heading_font = _font("Kenney Future.ttf")
	body_font = _font("Kenney Future Narrow.ttf")
	mono_font = _font("Kenney Mini.ttf")

	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = base_size

	# Labels
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_type_variation("HeaderLarge", "Label")
	t.set_font("font", "HeaderLarge", heading_font)
	t.set_font_size("font_size", "HeaderLarge", int(base_size * 2.2))
	t.set_type_variation("HeaderMedium", "Label")
	t.set_font("font", "HeaderMedium", heading_font)
	t.set_font_size("font_size", "HeaderMedium", int(base_size * 1.4))
	t.set_type_variation("InkLabel", "Label")
	t.set_color("font_color", "InkLabel", INK)
	t.set_constant("outline_size", "InkLabel", 0)
	t.set_type_variation("InkHeader", "Label")
	t.set_font("font", "InkHeader", heading_font)
	t.set_font_size("font_size", "InkHeader", int(base_size * 1.4))
	t.set_color("font_color", "InkHeader", INK)
	t.set_constant("outline_size", "InkHeader", 0)
	t.set_type_variation("InkTitle", "Label")
	t.set_font("font", "InkTitle", heading_font)
	t.set_font_size("font_size", "InkTitle", int(base_size * 1.9))
	t.set_color("font_color", "InkTitle", INK)
	t.set_constant("outline_size", "InkTitle", 0)
	t.set_type_variation("NameLabel", "Label")
	t.set_font("font", "NameLabel", heading_font)
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", int(base_size * 0.8))
	t.set_color("font_color", "HintLabel", Color(PARCHMENT, 0.8))

	# Buttons
	var normal := _tex_box("button_brown.png", 16, Vector4(22, 10, 22, 12))
	var hover := _tex_box("button_brown.png", 16, Vector4(22, 10, 22, 12))
	hover.modulate_color = Color(1.15, 1.1, 1.05)
	var pressed := _tex_box("button_brown.png", 16, Vector4(22, 12, 22, 10))
	pressed.modulate_color = Color(0.8, 0.75, 0.7)
	var disabled := _tex_box("button_grey.png", 16, Vector4(22, 10, 22, 12))
	disabled.modulate_color = Color(1, 1, 1, 0.6)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", _focus_fill_box())
	t.set_font("font", "Button", heading_font)
	t.set_font_size("font_size", "Button", base_size)
	# The button texture is light, so button text is ink.
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.BLACK)
	t.set_color("font_focus_color", "Button", Color.BLACK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.45))
	t.set_constant("outline_size", "Button", 0)

	t.set_type_variation("DangerButton", "Button")
	var danger := _tex_box("button_red.png", 16, Vector4(22, 10, 22, 12))
	t.set_stylebox("normal", "DangerButton", danger)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(c, "DangerButton", Color.WHITE)

	# Option buttons and check boxes share the button look
	for type in ["OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			t.set_stylebox(state, type, t.get_stylebox(state, "Button"))
		t.set_font("font", type, heading_font)
		t.set_font_size("font_size", type, base_size)
		t.set_color("font_color", type, INK)
	t.set_stylebox("focus", "CheckBox", _focus_box())
	t.set_stylebox("focus", "CheckButton", _focus_box())
	t.set_icon("checked", "CheckBox", _tex("checkbox_brown_checked.png"))
	t.set_icon("unchecked", "CheckBox", _tex("checkbox_brown_empty.png"))
	t.set_color("font_color", "CheckBox", PARCHMENT)
	t.set_color("font_focus_color", "CheckBox", Color.WHITE)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)

	# Panels
	var panel := _tex_box("panel_brown.png", 24, Vector4(24, 20, 24, 20))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_type_variation("DarkPanel", "PanelContainer")
	t.set_stylebox("panel", "DarkPanel", _tex_box("panel_brown_dark.png", 24, Vector4(24, 20, 24, 20)))
	t.set_type_variation("ParchmentPanel", "PanelContainer")
	var parchment := StyleBoxFlat.new()
	parchment.bg_color = PARCHMENT
	parchment.border_color = Color("8a5a32")
	parchment.set_border_width_all(6)
	parchment.set_corner_radius_all(14)
	parchment.set_content_margin_all(26)
	parchment.shadow_color = Color(0, 0, 0, 0.45)
	parchment.shadow_size = 10
	t.set_stylebox("panel", "ParchmentPanel", parchment)
	t.set_type_variation("GlassPanel", "PanelContainer")
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.05, 0.05, 0.1, 0.72)
	glass.set_corner_radius_all(12)
	glass.set_content_margin_all(14)
	t.set_stylebox("panel", "GlassPanel", glass)

	# Text entry
	var edit := _tex_box("panel_grey.png", 20, Vector4(16, 10, 16, 10))
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _focus_box())
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.5))
	t.set_font_size("font_size", "LineEdit", base_size)

	# Progress bars
	t.set_stylebox("background", "ProgressBar", _tex_box("progress_transparent.png", 14, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", _tex_box("progress_green.png", 14, Vector4(0, 0, 0, 0)))
	t.set_color("font_color", "ProgressBar", PARCHMENT)
	t.set_type_variation("RedProgressBar", "ProgressBar")
	t.set_stylebox("fill", "RedProgressBar", _tex_box("progress_red.png", 14, Vector4(0, 0, 0, 0)))
	t.set_type_variation("BlueProgressBar", "ProgressBar")
	t.set_stylebox("fill", "BlueProgressBar", _tex_box("progress_blue.png", 14, Vector4(0, 0, 0, 0)))

	# Sliders
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.2, 0.13, 0.08, 0.9)
	slider_bg.set_corner_radius_all(6)
	slider_bg.content_margin_top = 6
	slider_bg.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := slider_bg.duplicate() as StyleBoxFlat
	slider_fill.bg_color = Color("c98a4b")
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	t.set_stylebox("focus", "HSlider", _focus_box())

	# Scroll bars
	var grabber := _tex_box("scrollbar_brown.png", 14, Vector4(0, 0, 0, 0))
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.25)
	track.set_corner_radius_all(8)
	t.set_stylebox("scroll", "VScrollBar", track)

	# Item lists (server browser, player lists)
	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0, 0, 0, 0.25)
	list_bg.set_corner_radius_all(8)
	list_bg.set_content_margin_all(8)
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("focus", "ItemList", _focus_box())
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(FOCUS, 0.35)
	sel.set_corner_radius_all(6)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("cursor", "ItemList", _focus_box())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", PARCHMENT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_font_size("font_size", "ItemList", base_size)

	# Tooltips and rich text
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_font("normal_font", "RichTextLabel", body_font)
	t.set_font("bold_font", "RichTextLabel", heading_font)
	t.set_font_size("normal_font_size", "RichTextLabel", base_size)
	t.set_font_size("bold_font_size", "RichTextLabel", base_size)
	return t


## Button focus: a tinted fill plus a thick border, readable on light buttons.
static func _focus_fill_box() -> StyleBoxFlat:
	var box := _focus_box()
	box.draw_center = true
	box.bg_color = Color(FOCUS, 0.4)
	box.set_border_width_all(6)
	box.set_expand_margin_all(6)
	return box


static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = FOCUS
	box.set_border_width_all(4)
	box.set_corner_radius_all(10)
	box.set_expand_margin_all(5)
	return box


static func _tex_box(file: String, margin: int, content: Vector4) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _tex(file)
	box.set_texture_margin_all(margin)
	box.content_margin_left = content.x
	box.content_margin_top = content.y
	box.content_margin_right = content.z
	box.content_margin_bottom = content.w
	return box


static func _tex(file: String) -> Texture2D:
	return load(TEX + file)


static func _font(file: String) -> Font:
	var f: FontFile = load(FONTS + file)
	return f
