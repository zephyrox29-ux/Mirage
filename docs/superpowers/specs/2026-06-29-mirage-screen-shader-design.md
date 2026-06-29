# Mirage — Screen Shader Overlay Design Spec

**Date:** 2026-06-29
**Status:** Draft

## Overview

Mirage is a lightweight Windows desktop application that applies configurable post-processing shader effects to the entire screen. It operates as a transparent, click-through overlay rendered after all other compositing, modifying only final display output. Effects are triggered by user-configurable global hotkeys.

## Goals

- Apply real-time GPU shader effects to the entire desktop display
- Transparent full-screen overlay with mouse passthrough — non-invasive
- Pass cursor position, active window rect, and time to shaders for effect interaction
- Extremely lightweight: ~2MB exe, <1% CPU, ~20MB RAM, 60fps on integrated graphics
- Configured via JSON file only (GUI deferred to future version)
- v1 ships 3 example effects: color inversion, mouse-following magnifier, warm color temperature

## Non-goals (v1)

- GUI configuration panel
- Multi-monitor independent effects
- Compute Shader effects (pixel shader only)
- Audio-reactive effects
- Cross-platform support (Windows 10/11 only)

## Architecture

### Data Flow

```
config.json -> Config Manager -> hotkey-to-effect mapping
                                      |
Input Manager (keyboard hook + mouse poll + window info)
        |
        v
Uniform Buffer ----------------------------+
        |                                  |
Desktop -> DXGI Desktop Duplication -> GPU texture -> Pixel Shader -> SwapChain Present -> Display
                                                              |
                                                  (full-screen overlay window)
```

### Module Breakdown

```
Mirage/
  main.cpp                  WinMain entry point
  overlay_window.cpp/h      Full-screen transparent window management
  d3d11_renderer.cpp/h      D3D11 init, Desktop Duplication, render loop
  shader_manager.cpp/h      HLSL load/compile, effect switching, uniform passing
  input_manager.cpp/h       Low-level keyboard hook, mouse polling, window enumeration
  config_manager.cpp/h      JSON config parsing
  shaders/
    invert.hlsl             Color inversion
    magnifier.hlsl          Mouse-following magnifier
    warm_color.hlsl         Warm/cool color temperature
  config.json               User configuration
```

### Module Responsibilities

| Module | Responsibility | Interface |
|---|---|---|
| `overlay_window` | Create/destroy full-screen transparent window | `HWND create()`, `void destroy()` |
| `d3d11_renderer` | D3D11 device, SwapChain, Desktop Duplication, main render loop | `void init(HWND)`, `void render_frame(Shader*)` |
| `shader_manager` | Load/compile HLSL, switch active effect, update uniforms | `Shader* load(path)`, `void apply_uniforms(Mouse, Time, Params)` |
| `input_manager` | Global hotkey hook, mouse position, foreground window info | `bool install_hook()`, `InputState poll()` |
| `config_manager` | Parse JSON, build hotkey->effect map | `Config load(path)` |

### Dependencies

- d3d11.dll (Windows built-in)
- dxgi.dll (Windows built-in)
- dwmapi.dll (Windows built-in)
- d3dcompiler_47.dll (Windows built-in, for runtime HLSL compilation)
- nlohmann/json (header-only, bundled as single header)
- No other third-party libraries

## Overlay Window

### Window Properties

| Property | Value | Purpose |
|---|---|---|
| Style | `WS_POPUP \| WS_VISIBLE` | Borderless full-screen |
| Extended style | `WS_EX_TRANSPARENT` | Click-through (mouse passthrough) |
| | `WS_EX_TOPMOST` | Always on top |
| | `WS_EX_TOOLWINDOW` | Hidden from taskbar |
| | `WS_EX_NOACTIVATE` | Never steals focus |
| Size | Primary monitor resolution | Full-screen coverage |
| Auto-resize | On WM_DISPLAYCHANGE | Handle resolution changes |

Window is created/destroyed on demand — only present when at least one effect is active. When no effect is active, the window is hidden and no capture/rendering occurs (CPU usage ~0%).

## Render Loop

### Per-frame sequence

```
1. AcquireNextFrame()  ->  Desktop frame as GPU texture (~0.5ms GPU)
2. Check resolution     ->  Rebuild SwapChain if changed
3. Update uniform buffer ->  mouse_pos, time, resolution, window rect (~0.001ms CPU)
4. Bind desktop texture  ->  PSSetShaderResources()
5. Bind pixel shader     ->  PSSetShader()
6. DrawIndexed(3)        ->  Full-screen triangle (~0.3-1ms GPU)
7. Present(1, 0)         ->  SwapChain output to display
8. ReleaseFrame()
```

Total CPU time per frame: <1ms. GPU time: <2ms on integrated graphics at 1080p.

### Frame timing

- Target: 60fps (VSync-aligned via `Present(1, 0)`)
- D3D11 handles VSync natively — no manual throttling needed
- The 1-frame latency from Desktop Duplication is the minimum achievable without kernel-level/DWM injection

## Input Manager

### Keyboard

Uses `SetWindowsHookEx(WH_KEYBOARD_LL)` — low-level keyboard hook, does NOT consume events.

Hook callback records key state into `std::bitset<256>` and returns `CallNextHookEx()` immediately. No allocation, no file I/O, no locks in the hook callback.

Main loop reads `key_state` bitset at end of each frame, matches against configured hotkeys, and updates effect state machine.

### Trigger Modes

| Mode | Behavior |
|---|---|
| `hold` | Effect active while keys held, deactivated on release |
| `toggle` | Press toggles effect on/off |
| `oneshot` | Press triggers one animation cycle |
| `stack` | Can coexist with other effects (multiple toggles simultaneously) |

### Mouse

`GetCursorPos()` called once per frame from main loop. Passed to shader as `float2` in normalized UV coordinates.

### Foreground Window (optional, v1 best-effort)

`GetForegroundWindow()` + `GetWindowRect()` — passes active window rectangle to shader uniform buffer.

## Configuration

### File format

JSON file located next to the executable. Reloaded on F5 press.

```json
{
  "version": 1,
  "effects": [
    {
      "id": "invert",
      "name": "Color Inversion",
      "shader": "shaders/invert.hlsl",
      "hotkey": { "keys": ["ctrl", "shift", "i"], "mode": "toggle" }
    },
    {
      "id": "magnifier",
      "name": "Mouse Magnifier",
      "shader": "shaders/magnifier.hlsl",
      "hotkey": { "keys": ["ctrl", "shift", "m"], "mode": "hold" },
      "params": { "zoom": 2.0, "radius": 200 }
    },
    {
      "id": "warm_color",
      "name": "Warm Color Temperature",
      "shader": "shaders/warm_color.hlsl",
      "hotkey": { "keys": ["ctrl", "shift", "w"], "mode": "toggle" },
      "params": { "temperature": 6500 }
    }
  ]
}
```

### Rules

- `keys` support: `ctrl`, `shift`, `alt`, `win`, `a`-`z`, `0`-`9`, `f1`-`f12`, and special keys mapped from VK codes
- `mode`: one of `hold`, `toggle`, `oneshot`, `stack`
- `params`: optional, forwarded to shader as uniform values
- If multiple effects share a hotkey, first in file wins
- Missing or malformed config: app falls back to built-in defaults (3 example effects)

## Shader Uniform Interface

Every shader receives these uniforms automatically (injected by the engine into constant buffer register b0):

```hlsl
cbuffer MirageUniforms : register(b0) {
    float2 u_resolution;        // Screen resolution in pixels
    float2 u_mouse;             // Cursor position in pixels
    float  u_time;              // Seconds since effect activated
    float  u_time_delta;        // Frame delta in seconds
    float4 u_active_window;     // (left, top, right, bottom), -1 = unavailable
    // Custom params from config.json are auto-appended:
    float  u_param_zoom;        // Example: from config.params.zoom
    float  u_param_radius;      // Example: from config.params.radius
}
```

Shaders sample the desktop via:

```hlsl
Texture2D u_scene : register(t0);
SamplerState u_sampler : register(s0);
```

## v1 Shader Effects

### 1. Color Inversion (`invert.hlsl`)
One-line core: `color.rgb = 1.0 - color.rgb`
Validates full pipeline: capture -> process -> present.

### 2. Mouse Magnifier (`magnifier.hlsl`)
Circular region around cursor with smooth falloff. UV offset based on zoom factor and distance from cursor. Configurable zoom level and radius via params.

### 3. Warm Color Temperature (`warm_color.hlsl`)
RGB gain based on temperature parameter (1000K warm/red to 12000K cool/blue). Simple color matrix approximation.

The three effects cover: pure color transform, UV-space manipulation, and parameterized adjustment — providing templates for all future effects.

## Project Structure

```
Mirage/
  mirage.exe               (build output, ~2MB)
  config.json               (user configuration)
  shaders/                  (HLSL source files, compiled at runtime)
    invert.hlsl
    magnifier.hlsl
    warm_color.hlsl
```

## Build

- Compiler: MSVC (Visual Studio 2022 Build Tools or full IDE)
- Build system: CMake, single `CMakeLists.txt`
- Link: d3d11.lib, dxgi.lib, dwmapi.lib, d3dcompiler.lib (all Windows SDK)
- No package manager; nlohmann/json included as single header
