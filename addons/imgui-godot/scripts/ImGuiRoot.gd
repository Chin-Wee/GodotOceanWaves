extends Node

signal imgui_layout

const csharp_controller := "res://addons/imgui-godot/ImGuiGodot/ImGuiController.cs"
const csharp_sync := "res://addons/imgui-godot/ImGuiGodot/ImGuiSync.cs"

func _enter_tree():
    var has_csharp := false
    if ClassDB.class_exists("CSharpScript"):
        var script := load(csharp_sync)
        has_csharp = script.get_instance_base_type() == "Object"

    if ClassDB.class_exists("ImGuiController"):
        # native
        add_child(ClassDB.instantiate("ImGuiController"))
        if has_csharp:
            var obj: Object = load(csharp_sync).new()
            obj.SyncPtrs()
            obj.free()
    else:
        # C# only
        if has_csharp:
            add_child(load(csharp_controller).new())

func _ready():
    if Engine.is_editor_hint() or not OS.get_cmdline_args().has("--embedded"):
        return
    _use_local_input()

func _use_local_input():
    # Reuse the plugin's InputLocal backend: embedded window positions are not
    # reliable origins for converting desktop mouse coordinates.
    var layer := CanvasLayer.new()
    layer.layer = 128
    add_child(layer)
    var container := SubViewportContainer.new()
    container.stretch = true
    container.mouse_filter = Control.MOUSE_FILTER_PASS
    layer.add_child(container)
    container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var viewport := SubViewport.new()
    viewport.disable_3d = true
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    container.add_child(viewport)
    ImGuiGD.SetMainViewport(viewport)
