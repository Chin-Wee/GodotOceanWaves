# Graph Report - GodotOceanWaves  (2026-10-10)

## Corpus Check
- 24 files · ~867,157 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 115 file(s) not represented in the graph (top: .uid 29, .import 22, .gd 22)

## Summary
- 395 nodes · 550 edges · 18 communities
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 19 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `0de5ddda`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- ImGuiGD
- imgui-godot.h
- Input
- BackendNative
- State
- GodotImGuiWindow
- RdRenderer
- Q: investigate what it would take to replace fft with gerstner without changing anything else about the simulation
- ImGuiController
- ImGuiGodot.Internal
- CanvasRenderer
- Fonts
- .Image
- BackendNet
- ImGuiLayer
- ImGuiExtensions
- IRenderer
- GodotOceanWaves

## God Nodes (most connected - your core abstractions)
1. `State` - 25 edges
2. `RdRenderer` - 24 edges
3. `Input` - 20 edges
4. `ImGuiGodot.Internal` - 17 edges
5. `BackendNative` - 17 edges
6. `ImGuiController` - 16 edges
7. `CanvasRenderer` - 16 edges
8. `ImGuiGD` - 15 edges
9. `IBackend` - 15 edges
10. `GodotImGuiWindow` - 15 edges

## Surprising Connections (you probably didn't know these)
- `RdRenderer` --references--> `RenderingDevice`  [EXTRACTED]
  addons/imgui-godot/ImGuiGodot/Internal/RdRenderer.cs → addons/imgui-godot/ImGuiGodot/Internal/State.cs
- `BackendNative` --implements--> `IBackend`  [EXTRACTED]
  addons/imgui-godot/ImGuiGodot/Internal/BackendNative.cs → addons/imgui-godot/ImGuiGodot/Internal/IBackend.cs
- `BackendNet` --implements--> `IBackend`  [EXTRACTED]
  addons/imgui-godot/ImGuiGodot/Internal/BackendNet.cs → addons/imgui-godot/ImGuiGodot/Internal/IBackend.cs
- `CanvasRenderer` --implements--> `IRenderer`  [EXTRACTED]
  addons/imgui-godot/ImGuiGodot/Internal/CanvasRenderer.cs → addons/imgui-godot/ImGuiGodot/Internal/IRenderer.cs
- `State` --references--> `Fonts`  [EXTRACTED]
  addons/imgui-godot/ImGuiGodot/Internal/State.cs → addons/imgui-godot/ImGuiGodot/Internal/Fonts.cs

## Import Cycles
- None detected.

## Communities (18 total, 0 thin omitted)

### Community 0 - "ImGuiGD"
Cohesion: 0.07
Nodes (19): Action, Callable, FontFile, IntPtr, SubViewport, Texture2D, Viewport, ImGuiGD (+11 more)

### Community 1 - "imgui-godot.h"
Cohesion: 0.10
Nodes (29): AddFont(), BindTexture(), Connect(), GET_IMGUIGD(), GetAtlasUVs(), AtlasTexture, Callable, FontFile (+21 more)

### Community 2 - "Input"
Cohesion: 0.10
Nodes (16): ImGuiIOPtr, ImGuiKey, InputEvent, JoyButton, Key, SubViewport, Vector2, Input (+8 more)

### Community 3 - "BackendNative"
Cohesion: 0.07
Nodes (17): ImDrawVert, StringName, ImGuiSync, Callable, FontFile, GodotObject, StringName, SubViewport (+9 more)

### Community 4 - "State"
Cohesion: 0.08
Nodes (22): IntPtr, Vector2, Vector2I, RendererType, Canvas, Dummy, RenderingDevice, State (+14 more)

### Community 5 - "GodotImGuiWindow"
Cohesion: 0.11
Nodes (13): IntPtr, Vector2, Vector2I, Window, GodotImGuiWindow, ViewportsExts, ImGuiPlatformIO_Set_Platform_GetWindowPos(), ImGuiPlatformIO_Set_Platform_GetWindowSize() (+5 more)

### Community 6 - "RdRenderer"
Cohesion: 0.08
Nodes (21): Color, Dictionary, ImDrawDataPtr, ImDrawVert, IntPtr, Rid, RdRenderer, Name (+13 more)

### Community 7 - "Q: investigate what it would take to replace fft with gerstner without changing anything else about the simulation"
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: investigate what it would take to replace fft with gerstner without changing anything else about the simulation, Source Nodes

### Community 8 - "ImGuiController"
Cohesion: 0.13
Nodes (9): InputEvent, Viewport, Window, ImGuiController, Instance, Signaler, ImGuiControllerHelper, ImGuiControllerHelper (+1 more)

### Community 9 - "ImGuiGodot.Internal"
Cohesion: 0.12
Nodes (9): RdRendererException, Rid, Util, ApplicationException, ImGuiGodot.ImGuiNET, ImGuiGodot, ImGuiGodot.Internal, ImGuiGodot.ImGuiGodot (+1 more)

### Community 10 - "CanvasRenderer"
Cohesion: 0.18
Nodes (10): Dictionary, ImDrawDataPtr, List, Rid, CanvasRenderer, Name, ViewportData, Canvas (+2 more)

### Community 11 - "Fonts"
Cohesion: 0.17
Nodes (11): FontFile, List, Texture2D, FontParams, Font, FontSize, Merge, Ranges (+3 more)

### Community 12 - ".Image"
Cohesion: 0.29
Nodes (8): AtlasTexture, SubViewport, Texture2D, Vector2, Vector4, Widgets, uv0, uv1

### Community 13 - "BackendNet"
Cohesion: 0.12
Nodes (8): Callable, FontFile, SubViewport, Viewport, BackendNet, JoyAxisDeadZone, Scale, Visible

### Community 14 - "ImGuiLayer"
Cohesion: 0.16
Nodes (8): InputEvent, Node, Rid, Vector2I, Viewport, ImGuiLayer, CanvasLayer, Transform2D

### Community 15 - "ImGuiExtensions"
Cohesion: 0.19
Nodes (8): Color, ImGuiIOPtr, ImGuiKey, JoyButton, Key, Vector4, ImGuiExtensions, Vector3

### Community 16 - "IRenderer"
Cohesion: 0.13
Nodes (6): Rid, DummyRenderer, Name, Rid, IRenderer, Name

### Community 17 - "GodotOceanWaves"
Cohesion: 0.09
Nodes (21): Attribution, Daylight controls, Earlier validation — 2026-10-05 (source revision 7d48a1e), Embedded panel input, Fast Fourier Transform, Freecam, foam and reflections, GodotOceanWaves, Introduction (+13 more)

## Knowledge Gaps
- **61 isolated node(s):** `Instance`, `Signaler`, `JoyAxisDeadZone`, `Scale`, `Visible` (+56 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 180 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ImGuiGodot.Internal` connect `ImGuiGodot.Internal` to `ImGuiGD`, `Input`, `GodotImGuiWindow`, `RdRenderer`, `CanvasRenderer`, `BackendNet`, `IRenderer`?**
  _High betweenness centrality (0.310) - this node is a cross-community bridge._
- **Why does `State` connect `State` to `Input`, `RdRenderer`, `ImGuiGodot.Internal`, `Fonts`, `IRenderer`?**
  _High betweenness centrality (0.207) - this node is a cross-community bridge._
- **Why does `ImGuiGD` connect `ImGuiGD` to `ImGuiGodot.Internal`, `BackendNative`?**
  _High betweenness centrality (0.145) - this node is a cross-community bridge._
- **What connects `Instance`, `Signaler`, `JoyAxisDeadZone` to the rest of the system?**
  _61 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `ImGuiGD` be split into smaller, more focused modules?**
  _Cohesion score 0.06606606606606606 - nodes in this community are weakly interconnected._
- **Should `imgui-godot.h` be split into smaller, more focused modules?**
  _Cohesion score 0.09659090909090909 - nodes in this community are weakly interconnected._
- **Should `Input` be split into smaller, more focused modules?**
  _Cohesion score 0.10344827586206896 - nodes in this community are weakly interconnected._