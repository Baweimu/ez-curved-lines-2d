@tool
extends EditorPlugin

const META_NAME_HOVER_POINT_IDX := "_hover_point_idx_"
const META_NAME_HOVER_CP_IN_IDX := "_hover_cp_in_idx_"
const META_NAME_HOVER_CP_OUT_IDX := "_hover_cp_out_idx_"
const META_NAME_HOVER_CLOSEST_POINT := "_hover_closest_point_on_curve_"
const META_NAME_SELECT_HINT := "_select_hint_"
const VIEWPORT_ORANGE := Color(0.737, 0.463, 0.337)

var plugin
var svg_importer_dock
var select_mode_button : Button
var undo_redo : EditorUndoRedoManager

func _enter_tree():
	svg_importer_dock = preload("res://addons/curved_lines_2d/svg_importer_dock.tscn").instantiate()
	plugin = preload("res://addons/curved_lines_2d/line_2d_generator_inspector_plugin.gd").new()
	add_inspector_plugin(plugin)
	add_custom_type(
		"DrawablePath2D",
		"Path2D",
		preload("res://addons/curved_lines_2d/drawable_path_2d.gd"),
		preload("res://addons/curved_lines_2d/DrawablePath2D.svg")
	)
	add_custom_type(
		"ScalableVectorShape2D",
		"Node2D",
		preload("res://addons/curved_lines_2d/scalable_vector_shape_2d.gd"),
		preload("res://addons/curved_lines_2d/DrawablePath2D.svg")
	)
	undo_redo = get_undo_redo()
	add_control_to_bottom_panel(svg_importer_dock as Control, "EZ SVG Importer")
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	undo_redo.version_changed.connect(update_overlays)


func _on_selection_changed():
	var scene_root := EditorInterface.get_edited_scene_root()
	if is_instance_valid(scene_root):

		# inelegant fix to always keep an instance of Node selected, so
		# _forward_canvas_gui_input will still be called upon losing focus
		if (not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
				and EditorInterface.get_selection().get_selected_nodes().is_empty()):
			EditorInterface.edit_node(scene_root)
	update_overlays()


func _handles(object: Object) -> bool:
	return object is Node


func find_scalable_vector_shape_2d_nodes_at(pos : Vector2) -> Array[Node]:
	if is_instance_valid(EditorInterface.get_edited_scene_root()):
		return (EditorInterface.get_edited_scene_root()
					.find_children("*", "ScalableVectorShape2D")
					.filter(func(x : ScalableVectorShape2D): return x.has_point(pos)))
	return []


func _is_change_pivot_button_active() -> bool:
	var results = (
			EditorInterface.get_editor_viewport_2d().find_parent("*CanvasItemEditor*")
					.find_children("*Button*", "", true, false)
	)
	if results.size() >= 6:
		return results[5].button_pressed
	return false


func _get_select_mode_button() -> Button:
	if is_instance_valid(select_mode_button):
		return select_mode_button
	else:
		select_mode_button = (
			EditorInterface.get_editor_viewport_2d().find_parent("*CanvasItemEditor*")
					.find_child("*Button*", true, false)
		)
		return select_mode_button


func _vp_transform(p : Vector2) -> Vector2:
	var s := EditorInterface.get_editor_viewport_2d().get_final_transform().get_scale()
	var o := EditorInterface.get_editor_viewport_2d().get_final_transform().get_origin()
	return (p * s) + o


func _is_svs_valid(svs : Object) -> bool:
	return is_instance_valid(svs) and svs is ScalableVectorShape2D and svs.curve


func _handle_has_hover(svs : ScalableVectorShape2D) -> bool:
	return (
		svs.has_meta(META_NAME_HOVER_POINT_IDX) or
		svs.has_meta(META_NAME_HOVER_CP_IN_IDX) or
		svs.has_meta(META_NAME_HOVER_CP_OUT_IDX)
	)


func _draw_control_point_handle(viewport_control : Control, svs : ScalableVectorShape2D,
		handle : Dictionary, prefix : String, is_hovered := false) -> void:
	if handle[prefix].length():
		var color := VIEWPORT_ORANGE if is_hovered else Color.WHITE
		var width := 2 if is_hovered else 1
		viewport_control.draw_line(_vp_transform(handle['point_position']),
				_vp_transform(handle[prefix + '_position']), Color.WEB_GRAY, 1, true)
		viewport_control.draw_circle(_vp_transform(handle[prefix + '_position']), 5, Color.DIM_GRAY)
		viewport_control.draw_circle(_vp_transform(handle[prefix + '_position']), 5, color, false, width)


func _draw_handles(viewport_control : Control, svs : ScalableVectorShape2D) -> void:
	var handles = svs.get_curve_handles()
	for i in range(handles.size()):
		var handle = handles[i]
		var is_hovered : bool = svs.get_meta(META_NAME_HOVER_POINT_IDX, -1) == i
		var cp_in_is_hovered : bool = svs.get_meta(META_NAME_HOVER_CP_IN_IDX, -1) == i
		var cp_out_is_hovered : bool = svs.get_meta(META_NAME_HOVER_CP_OUT_IDX, -1) == i
		var color := VIEWPORT_ORANGE if is_hovered else Color.WHITE
		var width := 2 if is_hovered else 1
		_draw_control_point_handle(viewport_control, svs, handle, 'in', is_hovered or cp_in_is_hovered)
		_draw_control_point_handle(viewport_control, svs, handle, 'out', is_hovered or cp_out_is_hovered)
		if handle['mirrored']:
			# mirrored handles
			var rect := Rect2(_vp_transform(handle['point_position']) - Vector2(5, 5), Vector2(10, 10))
			viewport_control.draw_rect(rect, Color.DIM_GRAY, .5)
			viewport_control.draw_rect(rect, color, false, width)
		else:
			# unmirrored handles / zero length handles
			var p1 := _vp_transform(handle['point_position'])
			var pts := PackedVector2Array([
					Vector2(p1.x - 8, p1.y), Vector2(p1.x, p1.y - 8),
					Vector2(p1.x + 8, p1.y), Vector2(p1.x, p1.y + 8)
			])
			viewport_control.draw_polygon(pts, [Color.DIM_GRAY])
			pts.append(Vector2(p1.x - 8, p1.y))
			viewport_control.draw_polyline(pts, color, width)
		if is_hovered:
			var default_font = ThemeDB.fallback_font
			var default_font_size = ThemeDB.fallback_font_size
			viewport_control.draw_string(default_font, _vp_transform(handle['point_position']), str(i))


func _set_handle_hover(g_mouse_pos : Vector2, svs : ScalableVectorShape2D) -> void:
	var mouse_pos := _vp_transform(g_mouse_pos)
	var handles = svs.get_curve_handles()
	svs.remove_meta(META_NAME_HOVER_POINT_IDX)
	svs.remove_meta(META_NAME_HOVER_CP_IN_IDX)
	svs.remove_meta(META_NAME_HOVER_CP_OUT_IDX)
	for i in range(handles.size()):
		var handle = handles[i]
		if mouse_pos.distance_to(_vp_transform(handle['point_position'])) < 10:
			svs.set_meta(META_NAME_HOVER_POINT_IDX, i)
		elif mouse_pos.distance_to(_vp_transform(handle['in_position'])) < 10:
			svs.set_meta(META_NAME_HOVER_CP_IN_IDX, i)
		elif mouse_pos.distance_to(_vp_transform(handle['out_position'])) < 10:
			svs.set_meta(META_NAME_HOVER_CP_OUT_IDX, i)
	var closest_point_on_curve := svs.get_closest_point_on_curve(g_mouse_pos)

	if ("point_position" in closest_point_on_curve and
			mouse_pos.distance_to(_vp_transform(closest_point_on_curve["point_position"])) < 15
	):
		svs.set_meta(META_NAME_HOVER_CLOSEST_POINT, closest_point_on_curve)


func _draw_curve(viewport_control : Control, svs : ScalableVectorShape2D) -> void:
	var points = svs.get_poly_points().map(_vp_transform)
	var color := svs.shape_hint_color if svs.shape_hint_color else Color.LIME_GREEN
	var last_p := Vector2.INF
	for p : Vector2 in points:
		if last_p != Vector2.INF:
			viewport_control.draw_line(last_p, p, color, 1.0, true)
		last_p = p
	if is_instance_valid(svs.line) and svs.line.closed and points.size() > 1:
		viewport_control.draw_line(last_p, points[0], color, 1.0, true)


func _draw_closest_point_on_curve(viewport_control : Control, svs : ScalableVectorShape2D) -> void:
	if svs.has_meta(META_NAME_HOVER_CLOSEST_POINT):
		var md_p := svs.get_meta(META_NAME_HOVER_CLOSEST_POINT)
		print(md_p)
		var p = _vp_transform(md_p["point_position"])
		viewport_control.draw_line(p - 8 * Vector2.UP, p - 2 * Vector2.UP, Color.WEB_GRAY, 2)
		viewport_control.draw_line(p - 8 * Vector2.RIGHT, p - 2 * Vector2.RIGHT, Color.WEB_GRAY,2)
		viewport_control.draw_line(p - 8 * Vector2.DOWN, p - 2 * Vector2.DOWN, Color.WEB_GRAY, 2)
		viewport_control.draw_line(p - 8 * Vector2.LEFT, p - 2 * Vector2.LEFT, Color.WEB_GRAY, 2)
		viewport_control.draw_line(p - 8 * Vector2.UP, p - 2 * Vector2.UP, Color.WHITE)
		viewport_control.draw_line(p - 8 * Vector2.RIGHT, p - 2 * Vector2.RIGHT, Color.WHITE)
		viewport_control.draw_line(p - 8 * Vector2.DOWN, p - 2 * Vector2.DOWN, Color.WHITE)
		viewport_control.draw_line(p - 8 * Vector2.LEFT, p - 2 * Vector2.LEFT, Color.WHITE)


func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	if not is_instance_valid(EditorInterface.get_edited_scene_root()):
		return
	var current_selection := EditorInterface.get_selection().get_selected_nodes().pop_back()
	for result : ScalableVectorShape2D in EditorInterface.get_edited_scene_root().find_children("*", "ScalableVectorShape2D").filter(_is_svs_valid):
		if result == current_selection:
			viewport_control.draw_polyline(result.get_bounding_box().map(_vp_transform),
					VIEWPORT_ORANGE, 2.0)
			_draw_curve(viewport_control, result)
			_draw_handles(viewport_control, result)
			if not _handle_has_hover(result):
				_draw_closest_point_on_curve(viewport_control, result)
		elif result.has_meta(META_NAME_SELECT_HINT):
			viewport_control.draw_polyline(result.get_bounding_box().map(_vp_transform),
					Color.WEB_GRAY, 1.0)


func _update_curve_point_position(current_selection : ScalableVectorShape2D, mouse_pos : Vector2, idx : int) -> void:
	undo_redo.create_action("Move point on " + str(current_selection))
	if idx == 0 and current_selection.is_curve_closed():
		var idx_1 = current_selection.curve.point_count - 1
		undo_redo.add_do_method(current_selection, 'set_global_curve_point_position', mouse_pos, idx_1)
		undo_redo.add_undo_method(current_selection.curve, 'set_point_position', idx_1, current_selection.curve.get_point_position(idx_1))
	undo_redo.add_do_method(current_selection, 'set_global_curve_point_position', mouse_pos, idx)
	undo_redo.add_undo_method(current_selection.curve, 'set_point_position', idx, current_selection.curve.get_point_position(idx))
	undo_redo.commit_action()


func _update_curve_cp_in_position(current_selection : ScalableVectorShape2D, mouse_pos : Vector2, idx : int) -> void:
	if idx == 0:
		idx = current_selection.curve.point_count - 1
	undo_redo.create_action("Move control point in %d on %s" % [idx, current_selection])
	undo_redo.add_do_method(current_selection, 'set_global_curve_cp_in_position', mouse_pos, idx)
	undo_redo.add_undo_method(current_selection.curve, 'set_point_in', idx, current_selection.curve.get_point_in(idx))
	current_selection.set_global_curve_cp_in_position(mouse_pos, idx)
	if Input.is_key_pressed(KEY_SHIFT) and not(idx == current_selection.curve.point_count - 1 and not current_selection.is_curve_closed()):
		var idx_1 = 0 if idx == current_selection.curve.point_count - 1 else idx
		undo_redo.add_do_method(current_selection.curve, 'set_point_out', idx_1, -current_selection.curve.get_point_in(idx))
		undo_redo.add_undo_method(current_selection.curve, 'set_point_out', idx_1, current_selection.curve.get_point_out(idx_1))
		current_selection.curve.set_point_out(idx_1, -current_selection.curve.get_point_in(idx))
	undo_redo.commit_action(false)


func _update_curve_cp_out_position(current_selection : ScalableVectorShape2D, mouse_pos : Vector2, idx : int) -> void:
	if idx == current_selection.curve.point_count - 1:
		idx = 0
	undo_redo.create_action("Move control point out %d on %s" % [idx, current_selection])
	undo_redo.add_do_method(current_selection, 'set_global_curve_cp_out_position', mouse_pos, idx)
	undo_redo.add_undo_method(current_selection.curve, 'set_point_out', idx, current_selection.curve.get_point_out(idx))
	current_selection.set_global_curve_cp_out_position(mouse_pos, idx)
	if Input.is_key_pressed(KEY_SHIFT) and not(idx == 0 and not current_selection.is_curve_closed()):
		var idx_1 = current_selection.curve.point_count - 1 if idx == 0 else idx
		undo_redo.add_do_method(current_selection.curve, 'set_point_in', idx_1, -current_selection.curve.get_point_out(idx))
		undo_redo.add_undo_method(current_selection.curve, 'set_point_in', idx_1, current_selection.curve.get_point_in(idx_1))
		current_selection.curve.set_point_in(idx_1, -current_selection.curve.get_point_out(idx))
	undo_redo.commit_action(false)


func _set_shape_origin(current_selection : ScalableVectorShape2D, mouse_pos : Vector2) -> void:
	undo_redo.create_action("Set origin on %s" % current_selection)
	undo_redo.add_do_method(current_selection, 'set_origin', mouse_pos)
	undo_redo.add_undo_method(current_selection, 'set_origin', current_selection.global_position)
	undo_redo.commit_action()


func _get_curve_backup(curve_in : Curve2D) -> Curve2D:
	var curve_copy := Curve2D.new()
	for i in range(curve_in.point_count):
		curve_copy.add_point(curve_in.get_point_position(i),
				curve_in.get_point_in(i), curve_in.get_point_out(i))
	return curve_copy


func _remove_point_from_curve(current_selection : ScalableVectorShape2D, idx : int) -> void:
	var backup := _get_curve_backup(current_selection.curve)
	var orig_n := current_selection.curve.point_count
	undo_redo.create_action("Remove point %d from %s" % [idx, str(current_selection)])
	undo_redo.add_do_method(current_selection.curve, 'remove_point', idx)
	if orig_n > 0:
		undo_redo.add_do_method(current_selection.curve, 'set_point_in', 0, Vector2.ZERO)
	if orig_n > 1:
		undo_redo.add_do_method(current_selection.curve, 'set_point_out', orig_n - 2, Vector2.ZERO)
	undo_redo.add_undo_method(current_selection, 'replace_curve_points', backup)
	undo_redo.commit_action()


func _remove_cp_in_from_curve(current_selection : ScalableVectorShape2D, idx : int) -> void:
	if idx == 0:
		idx = current_selection.curve.point_count - 1
	undo_redo.create_action("Remove control point in %d from %s " % [idx, str(current_selection)])
	undo_redo.add_do_method(current_selection.curve, 'set_point_in', idx, Vector2.ZERO)
	undo_redo.add_undo_method(current_selection.curve, 'set_point_in', idx, current_selection.curve.get_point_in(idx))
	undo_redo.commit_action()


func _remove_cp_out_from_curve(current_selection : ScalableVectorShape2D, idx : int) -> void:
	if idx == current_selection.curve.point_count - 1:
		idx = 0
	undo_redo.create_action("Remove control point out %d from %s " % [idx, str(current_selection)])
	undo_redo.add_do_method(current_selection.curve, 'set_point_out', idx, Vector2.ZERO)
	undo_redo.add_undo_method(current_selection.curve, 'set_point_out', idx, current_selection.curve.get_point_out(idx))
	undo_redo.commit_action()


func _add_point_on_curve_segment(svs : ScalableVectorShape2D) -> void:
	if not svs.has_meta(META_NAME_HOVER_CLOSEST_POINT):
		return
	var md_closest_point := svs.get_meta(META_NAME_HOVER_CLOSEST_POINT)



func _forward_canvas_gui_input(event: InputEvent) -> bool:

	if not _is_change_pivot_button_active() and not _get_select_mode_button().button_pressed:
		return false

	if not is_instance_valid(EditorInterface.get_edited_scene_root()):
		return false

	var current_selection := EditorInterface.get_selection().get_selected_nodes().pop_back()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos := EditorInterface.get_editor_viewport_2d().get_mouse_position()

		if _is_change_pivot_button_active():
			if _is_svs_valid(current_selection):
				_set_shape_origin(current_selection, mouse_pos)
		else:
			if _is_svs_valid(current_selection) and _handle_has_hover(current_selection):
				return true
			elif _is_svs_valid(current_selection) and current_selection.has_meta(META_NAME_HOVER_CLOSEST_POINT):
				if event.double_click:
					_add_point_on_curve_segment(current_selection)
				elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					print("mouse down: curve drag mode")
				return true
			else:
				var results := find_scalable_vector_shape_2d_nodes_at(mouse_pos)
				var refined_result := results.rfind_custom(func(x): return x.has_fine_point(mouse_pos))
				if refined_result > -1 and results[refined_result]:
					EditorInterface.edit_node(results[refined_result])
					return true
				var result = results.pop_back()
				if is_instance_valid(result):
					EditorInterface.edit_node(result)
					return true
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_svs_valid(current_selection) and _handle_has_hover(current_selection):
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				if current_selection.has_meta(META_NAME_HOVER_POINT_IDX):
					_remove_point_from_curve(current_selection, current_selection.get_meta(META_NAME_HOVER_POINT_IDX))
				elif current_selection.has_meta(META_NAME_HOVER_CP_IN_IDX):
					_remove_cp_in_from_curve(current_selection, current_selection.get_meta(META_NAME_HOVER_CP_IN_IDX))
				elif current_selection.has_meta(META_NAME_HOVER_CP_OUT_IDX):
					_remove_cp_out_from_curve(current_selection, current_selection.get_meta(META_NAME_HOVER_CP_OUT_IDX))
			return true

	if event is InputEventMouseMotion:
		var mouse_pos := EditorInterface.get_editor_viewport_2d().get_mouse_position()
		for result in EditorInterface.get_edited_scene_root().find_children("*", "ScalableVectorShape2D"):
			result.remove_meta(META_NAME_SELECT_HINT)
		if _is_svs_valid(current_selection):
			current_selection.remove_meta(META_NAME_HOVER_CLOSEST_POINT)

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _is_svs_valid(current_selection):
			if _handle_has_hover(current_selection):
				if current_selection.has_meta(META_NAME_HOVER_POINT_IDX):
					var pt_idx : int = current_selection.get_meta(META_NAME_HOVER_POINT_IDX)
					if Input.is_key_pressed(KEY_SHIFT):
						if pt_idx == 0:
							_update_curve_cp_out_position(current_selection, mouse_pos, pt_idx)
						else:
							_update_curve_cp_in_position(current_selection, mouse_pos, pt_idx)
					else:
						_update_curve_point_position(current_selection, mouse_pos, pt_idx)
				elif current_selection.has_meta(META_NAME_HOVER_CP_IN_IDX):
					_update_curve_cp_in_position(current_selection, mouse_pos, current_selection.get_meta(META_NAME_HOVER_CP_IN_IDX))
				elif current_selection.has_meta(META_NAME_HOVER_CP_OUT_IDX):
					_update_curve_cp_out_position(current_selection, mouse_pos, current_selection.get_meta(META_NAME_HOVER_CP_OUT_IDX))
				update_overlays()
				return true
		else:
			for result : ScalableVectorShape2D in find_scalable_vector_shape_2d_nodes_at(mouse_pos):
				result.set_meta(META_NAME_SELECT_HINT, true)

			if _is_svs_valid(current_selection):
				_set_handle_hover(mouse_pos, current_selection)

		update_overlays()

	return false


func _exit_tree():
	remove_inspector_plugin(plugin)
	remove_custom_type("DrawablePath2D")
	remove_custom_type("ScalableVectorShape2D")
	remove_control_from_bottom_panel(svg_importer_dock)
	svg_importer_dock.free()
