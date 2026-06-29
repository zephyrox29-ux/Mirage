# Mirage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-screen transparent overlay that captures the desktop via DXGI Desktop Duplication, applies configurable pixel shader effects, and presents the result with zero-capture mouse passthrough.

**Architecture:** C++ Win32 app with D3D11 rendering. Desktop frames are captured via DXGI Desktop Duplication API, processed through HLSL pixel shaders with per-frame uniform data (mouse pos, time, resolution), and presented via a borderless topmost transparent overlay window. Effects and hotkeys are configured via a JSON file.

**Tech Stack:** C++17, D3D11, DXGI, HLSL (ps_5_0), nlohmann/json, CMake + MSVC

## Global Constraints

- Windows 10/11 only, integrated graphics sufficient, 60fps target
- Single ~2MB exe, no installer, no runtime dependencies outside Windows built-in DLLs
- No GUI — config via JSON file next to exe only
- Click-through overlay via WS_EX_TRANSPARENT — never blocks mouse interaction
- v1 ships 3 effects: color inversion, mouse magnifier, warm color temperature
- No Compute Shader, no multi-monitor, no audio reactivity

---

## File Structure

```
Mirage/
├── CMakeLists.txt
├── .gitignore
├── config.json
├── external/
│   └── json.hpp              (nlohmann/json single header)
├── shaders/
│   ├── invert.hlsl
│   ├── magnifier.hlsl
│   └── warm_color.hlsl
└── src/
    ├── main.cpp
    ├── config_manager.h
    ├── config_manager.cpp
    ├── overlay_window.h
    ├── overlay_window.cpp
    ├── input_manager.h
    ├── input_manager.cpp
    ├── shader_manager.h
    ├── shader_manager.cpp
    ├── d3d11_renderer.h
    └── d3d11_renderer.cpp
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `CMakeLists.txt`
- Create: `.gitignore`
- Create: `external/json.hpp` (downloaded)
- Create: `src/main.cpp` (skeleton)

**Interfaces:**
- Produces: Buildable CMake project that compiles an empty WinMain exe, links against d3d11/dxgi/dwmapi/d3dcompiler

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p d:/my_project_for_D/Mirage/src
mkdir -p d:/my_project_for_D/Mirage/shaders
mkdir -p d:/my_project_for_D/Mirage/external
```

- [ ] **Step 2: Download nlohmann/json single header**

```bash
curl -L -o d:/my_project_for_D/Mirage/external/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp
```

Expected: `external/json.hpp` exists, ~900KB.

- [ ] **Step 3: Write `.gitignore`**

```gitignore
build/
*.exe
*.pdb
*.ilk
*.obj
```

- [ ] **Step 4: Write `CMakeLists.txt`**

```cmake
cmake_minimum_required(VERSION 3.16)
project(Mirage LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Release build for small exe
set(CMAKE_CXX_FLAGS_RELEASE "/MT /O2 /Ob2 /DNDEBUG")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "/OPT:REF /OPT:ICF")

# Use static CRT for single exe distribution
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(mirage
    src/main.cpp
    src/config_manager.cpp
    src/overlay_window.cpp
    src/input_manager.cpp
    src/shader_manager.cpp
    src/d3d11_renderer.cpp
)

target_include_directories(mirage PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/external
)

target_link_libraries(mirage
    d3d11
    dxgi
    dwmapi
    d3dcompiler
)

# Subsystem:Windows = no console window
set_target_properties(mirage PROPERTIES
    WIN32_EXECUTABLE TRUE
)
```

- [ ] **Step 5: Write `src/main.cpp` skeleton**

```cpp
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int nCmdShow) {
    return 0;
}
```

- [ ] **Step 6: Configure and build to verify scaffolding**

```bash
cd d:/my_project_for_D/Mirage
cmake -B build -S .
cmake --build build --config Release
```

Expected: Build succeeds, `build/Release/mirage.exe` exists.

- [ ] **Step 7: Commit**

```bash
git add CMakeLists.txt .gitignore external/json.hpp src/main.cpp
git commit -m "feat: project scaffolding with CMake and WinMain skeleton"
```

---

### Task 2: Config Manager

**Files:**
- Create: `src/config_manager.h`
- Create: `src/config_manager.cpp`

**Interfaces:**
- Produces:
  - `struct HotkeyConfig { std::vector<std::string> keys; std::string mode; };`
  - `struct EffectConfig { std::string id; std::string name; std::string shader_path; std::string mode; std::vector<std::string> keys; std::map<std::string, float> params; };`
  - `struct Config { int version; std::vector<EffectConfig> effects; };`
  - `Config load_config(const std::string& path);` — loads JSON, returns config; on any failure returns built-in defaults

- [ ] **Step 1: Write `src/config_manager.h`**

```cpp
#pragma once
#include <string>
#include <vector>
#include <map>

struct HotkeyConfig {
    std::vector<std::string> keys;
    std::string mode; // "hold", "toggle", "oneshot", "stack"
};

struct EffectConfig {
    std::string id;
    std::string name;
    std::string shader_path;
    std::string mode;           // copied from hotkey.mode for convenience
    std::vector<std::string> keys; // copied from hotkey.keys
    std::map<std::string, float> params; // ordered for deterministic shader param mapping
};

struct Config {
    int version = 0;
    std::vector<EffectConfig> effects;
};

Config load_config(const std::string& path);
```

- [ ] **Step 2: Write `src/config_manager.cpp`**

```cpp
#include "config_manager.h"
#include <fstream>
#include <json.hpp>

using json = nlohmann::json;

static Config build_defaults() {
    Config c;
    c.version = 1;
    c.effects = {
        {
            "invert", "Color Inversion", "shaders/invert.hlsl", "toggle",
            {"ctrl", "shift", "i"}, {}
        },
        {
            "magnifier", "Mouse Magnifier", "shaders/magnifier.hlsl", "hold",
            {"ctrl", "shift", "m"}, {{"zoom", 2.0f}, {"radius", 200.0f}}
        },
        {
            "warm_color", "Warm Color Temp", "shaders/warm_color.hlsl", "toggle",
            {"ctrl", "shift", "w"}, {{"temperature", 6500.0f}}
        },
    };
    return c;
}

Config load_config(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) return build_defaults();

    try {
        json j = json::parse(f);
        Config c;
        c.version = j.value("version", 1);

        for (const auto& ej : j.at("effects")) {
            EffectConfig ec;
            ec.id = ej.at("id").get<std::string>();
            ec.name = ej.value("name", ec.id);
            ec.shader_path = ej.at("shader").get<std::string>();

            const auto& hk = ej.at("hotkey");
            ec.keys = hk.at("keys").get<std::vector<std::string>>();
            ec.mode = hk.at("mode").get<std::string>();

            if (ej.contains("params")) {
                for (const auto& [k, v] : ej.at("params").items()) {
                    ec.params[k] = v.get<float>();
                }
            }
            c.effects.push_back(ec);
        }
        return c;
    } catch (...) {
        return build_defaults();
    }
}
```

- [ ] **Step 3: Write `config.json` (place in project root)**

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

- [ ] **Step 4: Verify compilation**

```bash
cd d:/my_project_for_D/Mirage
cmake --build build --config Release
```

Expected: Build succeeds with config_manager.cpp compiled.

- [ ] **Step 5: Commit**

```bash
git add src/config_manager.h src/config_manager.cpp config.json
git commit -m "feat: config manager with JSON parsing and built-in defaults"
```

---

### Task 3: Overlay Window

**Files:**
- Create: `src/overlay_window.h`
- Create: `src/overlay_window.cpp`

**Interfaces:**
- Produces: `HWND create_overlay_window(HINSTANCE hInstance, int width, int height);`
- Produces: `void destroy_overlay_window(HWND hwnd);`
- Produces: `void get_screen_size(int& width, int& height);`
- Internal: Window class registers on first call, handles WM_DISPLAYCHANGE, WM_CLOSE

- [ ] **Step 1: Write `src/overlay_window.h`**

```cpp
#pragma once
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

HWND create_overlay_window(HINSTANCE hInstance, int width, int height);
void destroy_overlay_window(HWND hwnd);
void get_screen_size(int& width, int& height);
```

- [ ] **Step 2: Write `src/overlay_window.cpp`**

```cpp
#include "overlay_window.h"

static const wchar_t* WINDOW_CLASS = L"MirageOverlay";

static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_DISPLAYCHANGE: {
        int w = (int)(lParam & 0xFFFF);
        int h = (int)(lParam >> 16);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        return 0;
    }
    case WM_CLOSE:
        return 0; // ignore, we close programmatically only
    case WM_ERASEBKGND:
        return 1; // skip background erase
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void get_screen_size(int& width, int& height) {
    width  = GetSystemMetrics(SM_CXSCREEN);
    height = GetSystemMetrics(SM_CYSCREEN);
}

HWND create_overlay_window(HINSTANCE hInstance, int width, int height) {
    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(WNDCLASSEXW);
    wc.lpfnWndProc   = wnd_proc;
    wc.hInstance     = hInstance;
    wc.lpszClassName = WINDOW_CLASS;
    wc.hCursor       = nullptr;
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);

    static bool registered = false;
    if (!registered) {
        RegisterClassExW(&wc);
        registered = true;
    }

    DWORD ex_style = WS_EX_TRANSPARENT | WS_EX_TOPMOST
                   | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    DWORD style = WS_POPUP;

    HWND hwnd = CreateWindowExW(
        ex_style, WINDOW_CLASS, L"Mirage", style,
        0, 0, width, height,
        nullptr, nullptr, hInstance, nullptr
    );

    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    return hwnd;
}

void destroy_overlay_window(HWND hwnd) {
    if (hwnd) DestroyWindow(hwnd);
}
```

- [ ] **Step 3: Verify compilation**

```bash
cmake --build build --config Release
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/overlay_window.h src/overlay_window.cpp
git commit -m "feat: full-screen transparent overlay window"
```

---

### Task 4: Input Manager

**Files:**
- Create: `src/input_manager.h`
- Create: `src/input_manager.cpp`

**Interfaces:**
- Consumes: `EffectConfig` from Task 2 (config_manager.h)
- Produces:
  - `void input_init();` — installs keyboard hook
  - `void input_shutdown();` — removes keyboard hook
  - `void input_update(const std::vector<EffectConfig>& effects);` — called each frame, updates effect states
  - `const std::vector<bool>& input_effect_active_states();` — returns active flag per effect (index-aligned with effects vector)
  - `float input_mouse_x();` — current mouse X in pixels
  - `float input_mouse_y();` — current mouse Y in pixels
  - `float input_time_delta();` — frame time delta in seconds
  - `void input_clear_reload_flag();` — clears the F5 reload flag after handling
  - `bool input_should_reload();` — whether F5 was pressed since last clear

**Effect state machine (internal):**
```
For each effect, track: bool active, bool prev_keys_down

Per-frame update:
  is_down = all keys in effect.keys are currently held
  rising_edge = is_down && !prev_keys_down

  if mode == "hold":     active = is_down
  if mode == "toggle":   if rising_edge: active = !active
  if mode == "oneshot":  if rising_edge: active = true; start_timer
                         if active && timer > 2.0: active = false
  if mode == "stack":    if rising_edge: active = !active

  prev_keys_down = is_down
```

- [ ] **Step 1: Write `src/input_manager.h`**

```cpp
#pragma once
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <vector>
#include <string>

struct EffectConfig; // forward decl from config_manager.h

void input_init();
void input_shutdown();
void input_update(const std::vector<EffectConfig>& effects);
const std::vector<bool>& input_effect_active_states();
float input_mouse_x();
float input_mouse_y();
float input_time_delta();
void input_clear_reload_flag();
bool input_should_reload();
```

- [ ] **Step 2: Write `src/input_manager.cpp`**

```cpp
#include "input_manager.h"
#include "config_manager.h"
#include <bitset>
#include <unordered_map>
#include <chrono>

static HHOOK g_keyboard_hook = nullptr;
static std::bitset<256> g_key_state;
static std::unordered_map<std::string, UINT> g_name_to_vk;

// Per-effect runtime state
struct EffectState {
    bool active = false;
    bool prev_keys_down = false;
    float start_time = 0.0f; // for oneshot
};
static std::vector<EffectState> g_effect_states;

// Frame timing
static LARGE_INTEGER g_freq;
static LARGE_INTEGER g_last_time;
static float g_time_delta = 0.0f;

// Mouse
static float g_mouse_x = 0.0f;
static float g_mouse_y = 0.0f;

// Reload flag
static bool g_should_reload = false;

static LRESULT CALLBACK low_level_keyboard_proc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION) {
        KBDLLHOOKSTRUCT* kb = (KBDLLHOOKSTRUCT*)lParam;
        UINT vk = kb->vkCode;
        bool down = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);

        if (vk < 256) g_key_state[vk] = down;

        // F5 reload
        if (vk == VK_F5 && down) {
            g_should_reload = true;
        }
    }
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

static void init_vk_map() {
    if (!g_name_to_vk.empty()) return;
    g_name_to_vk["ctrl"]  = VK_CONTROL;
    g_name_to_vk["shift"] = VK_SHIFT;
    g_name_to_vk["alt"]   = VK_MENU;
    g_name_to_vk["win"]   = VK_LWIN;
    g_name_to_vk["space"] = VK_SPACE;
    g_name_to_vk["tab"]   = VK_TAB;
    g_name_to_vk["escape"] = VK_ESCAPE;
    g_name_to_vk["enter"]  = VK_RETURN;
    g_name_to_vk["backspace"] = VK_BACK;
    g_name_to_vk["left"]  = VK_LEFT;
    g_name_to_vk["right"] = VK_RIGHT;
    g_name_to_vk["up"]    = VK_UP;
    g_name_to_vk["down"]  = VK_DOWN;
    for (int i = 0; i < 12; i++) {
        g_name_to_vk["f" + std::to_string(i + 1)] = VK_F1 + i;
    }
    for (char c = 'a'; c <= 'z'; c++) {
        g_name_to_vk[std::string(1, c)] = (UINT)(c - 'a' + 'A');
    }
    for (char c = '0'; c <= '9'; c++) {
        g_name_to_vk[std::string(1, c)] = (UINT)(c - '0' + '0');
    }
}

static bool is_modifier_name(const std::string& key) {
    return key == "ctrl" || key == "shift" || key == "alt" || key == "win";
}

static bool is_key_down(const std::string& key) {
    UINT vk = g_name_to_vk.at(key);
    if (key == "ctrl")  return g_key_state[VK_LCONTROL] || g_key_state[VK_RCONTROL];
    if (key == "shift") return g_key_state[VK_LSHIFT] || g_key_state[VK_RSHIFT];
    if (key == "alt")   return g_key_state[VK_LMENU] || g_key_state[VK_RMENU];
    if (key == "win")   return g_key_state[VK_LWIN] || g_key_state[VK_RWIN];
    return g_key_state[vk];
}

void input_init() {
    init_vk_map();
    g_keyboard_hook = SetWindowsHookExW(WH_KEYBOARD_LL, low_level_keyboard_proc,
                                         GetModuleHandleW(nullptr), 0);
    QueryPerformanceFrequency(&g_freq);
    QueryPerformanceCounter(&g_last_time);
}

void input_shutdown() {
    if (g_keyboard_hook) {
        UnhookWindowsHookEx(g_keyboard_hook);
        g_keyboard_hook = nullptr;
    }
}

void input_update(const std::vector<EffectConfig>& effects) {
    // Update frame timing
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    g_time_delta = (float)(now.QuadPart - g_last_time.QuadPart) / (float)g_freq.QuadPart;
    g_last_time = now;

    // Update mouse
    POINT pt;
    GetCursorPos(&pt);
    g_mouse_x = (float)pt.x;
    g_mouse_y = (float)pt.y;

    // Ensure state vector matches effects
    if (g_effect_states.size() != effects.size()) {
        g_effect_states.resize(effects.size());
    }

    // Update effect state machine
    float current_time = (float)(now.QuadPart) / (float)g_freq.QuadPart;
    for (size_t i = 0; i < effects.size(); i++) {
        auto& state = g_effect_states[i];
        const auto& cfg = effects[i];

        // Check if all hotkey keys are down
        bool all_down = true;
        for (const auto& key : cfg.keys) {
            if (!is_key_down(key)) {
                all_down = false;
                break;
            }
        }

        bool rising = all_down && !state.prev_keys_down;
        state.prev_keys_down = all_down;

        if (cfg.mode == "hold") {
            state.active = all_down;
        } else if (cfg.mode == "toggle" || cfg.mode == "stack") {
            if (rising) state.active = !state.active;
        } else if (cfg.mode == "oneshot") {
            if (rising) {
                state.active = true;
                state.start_time = current_time;
            }
            if (state.active && (current_time - state.start_time) > 2.0f) {
                state.active = false;
            }
        }
    }
}

static std::vector<bool> g_active_cache;

const std::vector<bool>& input_effect_active_states() {
    g_active_cache.resize(g_effect_states.size());
    for (size_t i = 0; i < g_effect_states.size(); i++) {
        g_active_cache[i] = g_effect_states[i].active;
    }
    return g_active_cache;
}

float input_mouse_x()  { return g_mouse_x; }
float input_mouse_y()  { return g_mouse_y; }
float input_time_delta() { return g_time_delta; }
void input_clear_reload_flag() { g_should_reload = false; }
bool input_should_reload() { return g_should_reload; }
```

- [ ] **Step 3: Verify compilation**

```bash
cmake --build build --config Release
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/input_manager.h src/input_manager.cpp
git commit -m "feat: input manager with keyboard hook and effect state machine"
```

---

### Task 5: Shader Manager

**Files:**
- Create: `src/shader_manager.h`
- Create: `src/shader_manager.cpp`

**Interfaces:**
- Consumes: `EffectConfig` from Task 2, D3D11 device/context from Task 6
- Produces:
  - `struct Shader { ID3D11PixelShader* ps; ID3D11Buffer* cbuffer; int param_count; float param_values[4]; };`
  - `Shader* shader_load(ID3D11Device* device, const EffectConfig& cfg);` — compiles HLSL, creates cbuffer
  - `void shader_unload(Shader* s);` — releases D3D11 resources
  - `void shader_update_cbuffer(ID3D11DeviceContext* ctx, Shader* s, float mx, float my, float time, float dt, int w, int h);` — updates constant buffer with current uniform values
  - Internal: Vertex shader is a single pre-compiled blob shared by all effects
  - Internal: Each pixel shader .hlsl source is read from disk, prepended with a shader header (cbuffer + texture declarations + param defines generated from config), compiled with D3DCompile

**Constant buffer layout (C++ side, must match HLSL cbuffer MirageUniforms):**
```cpp
#pragma pack(push, 16)
struct MirageUniforms {
    float resolution[2];      // offset 0,   size 8
    float mouse[2];           // offset 8,   size 8
    float time;               // offset 16,  size 4
    float time_delta;         // offset 20,  size 4
    float _pad[2];            // offset 24,  size 8 (padding for float4 alignment)
    float active_window[4];   // offset 32,  size 16
    float params[4];          // offset 48,  size 16
};
#pragma pack(pop)
static_assert(sizeof(MirageUniforms) == 64, "CBuffer size must be 64 bytes");
```

- [ ] **Step 1: Write `src/shader_manager.h`**

```cpp
#pragma once
#include <d3d11.h>
#include <string>
#include "config_manager.h"

struct Shader {
    ID3D11PixelShader* ps = nullptr;
    ID3D11Buffer* cbuffer = nullptr;
    int param_count = 0;
    float param_values[4] = {0, 0, 0, 0};
};

ID3D11VertexShader* shader_get_builtin_vs(ID3D11Device* device);
ID3D11InputLayout*  shader_get_input_layout(ID3D11Device* device);
Shader* shader_load(ID3D11Device* device, const EffectConfig& cfg);
void    shader_unload(Shader* s);
void    shader_update_cbuffer(ID3D11DeviceContext* ctx, Shader* s,
                              float mx, float my, float time, float dt, int w, int h);
```

- [ ] **Step 2: Write `src/shader_manager.cpp`**

```cpp
#include "shader_manager.h"
#include <d3dcompiler.h>
#include <fstream>
#include <sstream>
#include <cstdio>

#pragma pack(push, 16)
struct MirageUniforms {
    float resolution[2];
    float mouse[2];
    float time;
    float time_delta;
    float _pad[2];
    float active_window[4];
    float params[4];
};
#pragma pack(pop)
static_assert(sizeof(MirageUniforms) == 64, "CBuffer size mismatch");

// Built-in vertex shader (full-screen pass-through triangle)
static const char* g_vs_source = R"(
struct VS_INPUT  { float2 pos : POSITION; float2 uv : TEXCOORD0; };
struct PS_INPUT  { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
PS_INPUT main(VS_INPUT input) {
    PS_INPUT o;
    o.pos = float4(input.pos, 0.0, 1.0);
    o.uv  = input.uv;
    return o;
}
)";

// Header prepended to every pixel shader source
static const char* g_ps_header = R"(
cbuffer MirageUniforms : register(b0) {
    float2 u_resolution;
    float2 u_mouse;
    float  u_time;
    float  u_time_delta;
    float4 u_active_window;
    float4 u_params;
};
Texture2D    u_scene   : register(t0);
SamplerState u_sampler : register(s0);

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};
)";

static ID3D11VertexShader* g_cached_vs = nullptr;
static ID3D11InputLayout*  g_cached_layout = nullptr;

ID3D11VertexShader* shader_get_builtin_vs(ID3D11Device* device) {
    if (g_cached_vs) return g_cached_vs;

    ID3DBlob* blob = nullptr;
    ID3DBlob* err  = nullptr;
    HRESULT hr = D3DCompile(g_vs_source, strlen(g_vs_source), "vs", nullptr, nullptr,
                            "main", "vs_5_0", 0, 0, &blob, &err);
    if (FAILED(hr)) {
        if (err) OutputDebugStringA((const char*)err->GetBufferPointer());
        if (err) err->Release();
        return nullptr;
    }

    device->CreateVertexShader(blob->GetBufferPointer(), blob->GetBufferSize(),
                               nullptr, &g_cached_vs);

    D3D11_INPUT_ELEMENT_DESC layout[] = {
        { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 8, D3D11_INPUT_PER_VERTEX_DATA, 0 },
    };
    device->CreateInputLayout(layout, 2, blob->GetBufferPointer(),
                              blob->GetBufferSize(), &g_cached_layout);
    blob->Release();
    return g_cached_vs;
}

ID3D11InputLayout* shader_get_input_layout(ID3D11Device* device) {
    shader_get_builtin_vs(device); // ensures layout is created
    return g_cached_layout;
}

// Generate #define lines for custom params, e.g., "#define u_param_zoom u_params.x\n"
static std::string generate_param_defines(const EffectConfig& cfg) {
    std::string defs;
    int idx = 0;
    const char* swizzle[] = { "x", "y", "z", "w" };
    for (const auto& [name, value] : cfg.params) {
        if (idx >= 4) break;
        char buf[256];
        snprintf(buf, sizeof(buf), "#define u_param_%s u_params.%s\n", name.c_str(), swizzle[idx]);
        defs += buf;
        idx++;
    }
    return defs;
}

Shader* shader_load(ID3D11Device* device, const EffectConfig& cfg) {
    // Read pixel shader source from file
    std::ifstream f(cfg.shader_path);
    if (!f.is_open()) return nullptr;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string ps_source = ss.str();

    // Build full source: header + param defines + user pixel shader code
    std::string full_source = std::string(g_ps_header) + generate_param_defines(cfg) + ps_source;

    // Compile pixel shader
    ID3DBlob* blob = nullptr;
    ID3DBlob* err  = nullptr;
    HRESULT hr = D3DCompile(full_source.c_str(), full_source.size(), cfg.shader_path.c_str(),
                            nullptr, nullptr, "main", "ps_5_0", 0, 0, &blob, &err);
    if (FAILED(hr)) {
        if (err) {
            OutputDebugStringA((const char*)err->GetBufferPointer());
            err->Release();
        }
        return nullptr;
    }

    auto* s = new Shader();
    device->CreatePixelShader(blob->GetBufferPointer(), blob->GetBufferSize(), nullptr, &s->ps);
    blob->Release();

    // Create constant buffer
    D3D11_BUFFER_DESC cb_desc = {};
    cb_desc.ByteWidth = sizeof(MirageUniforms);
    cb_desc.Usage = D3D11_USAGE_DYNAMIC;
    cb_desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cb_desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    device->CreateBuffer(&cb_desc, nullptr, &s->cbuffer);

    // Store param values
    s->param_count = 0;
    for (const auto& [name, value] : cfg.params) {
        if (s->param_count >= 4) break;
        s->param_values[s->param_count++] = value;
    }

    return s;
}

void shader_unload(Shader* s) {
    if (!s) return;
    if (s->ps) s->ps->Release();
    if (s->cbuffer) s->cbuffer->Release();
    delete s;
}

void shader_update_cbuffer(ID3D11DeviceContext* ctx, Shader* s,
                            float mx, float my, float time, float dt, int w, int h) {
    MirageUniforms u = {};
    u.resolution[0] = (float)w;
    u.resolution[1] = (float)h;
    u.mouse[0] = mx;
    u.mouse[1] = my;
    u.time = time;
    u.time_delta = dt;

    // Active window rect (best-effort)
    HWND fg = GetForegroundWindow();
    RECT r = {};
    if (fg && GetWindowRect(fg, &r)) {
        u.active_window[0] = (float)r.left;
        u.active_window[1] = (float)r.top;
        u.active_window[2] = (float)r.right;
        u.active_window[3] = (float)r.bottom;
    } else {
        u.active_window[0] = u.active_window[1] =
        u.active_window[2] = u.active_window[3] = -1.0f;
    }

    for (int i = 0; i < s->param_count; i++) {
        u.params[i] = s->param_values[i];
    }

    D3D11_MAPPED_SUBRESOURCE mapped;
    ctx->Map(s->cbuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    memcpy(mapped.pData, &u, sizeof(MirageUniforms));
    ctx->Unmap(s->cbuffer, 0);
}
```

- [ ] **Step 3: Verify compilation**

```bash
cmake --build build --config Release
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/shader_manager.h src/shader_manager.cpp
git commit -m "feat: shader manager with HLSL compilation and constant buffer"
```

---

### Task 6: D3D11 Renderer

**Files:**
- Create: `src/d3d11_renderer.h`
- Create: `src/d3d11_renderer.cpp`

**Interfaces:**
- Consumes: `Shader` from Task 5, overlay window HWND from Task 3
- Produces:
  - `bool renderer_init(HWND hwnd);` — creates D3D11 device, SwapChain, Desktop Duplication, intermediate textures, vertex buffer
  - `void renderer_resize(int w, int h);` — rebuilds SwapChain and intermediate textures for new resolution
  - `void renderer_render_frame(const std::vector<Shader*>& active_shaders);` — capture, multi-effect compositing with ping-pong, present
  - `void renderer_shutdown();` — release all resources
  - `ID3D11Device* renderer_get_device();`
  - `ID3D11DeviceContext* renderer_get_context();`
  - `int renderer_width();`, `int renderer_height();`

**Multi-effect compositing:**
```
When N active effects:
  source = captured desktop texture
  for i = 0 to N-1:
    if N == 1: target = backbuffer RTV
    elif i == N-1: target = backbuffer RTV, source = last intermediate texture SRV
    elif i == 0: target = intermediate_rtv[0], source = capture SRV
    else: target = intermediate_rtv[dst_idx], source = intermediate_srv[1-dst_idx]
    bind source as t0, set shader i's PS + cbuffer, Draw(3), dst_idx ^= 1
  Present
```

- [ ] **Step 1: Write `src/d3d11_renderer.h`**

```cpp
#pragma once
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <d3d11.h>
#include <vector>
#include "shader_manager.h"

bool renderer_init(HWND hwnd);
void renderer_resize(int w, int h);
void renderer_render_frame(const std::vector<Shader*>& active_shaders);
void renderer_shutdown();

ID3D11Device*        renderer_get_device();
ID3D11DeviceContext* renderer_get_context();
int renderer_width();
int renderer_height();
```

- [ ] **Step 2: Write `src/d3d11_renderer.cpp`**

```cpp
#include "d3d11_renderer.h"
#include <dxgi1_2.h>
#include <cstdio>

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

// Full-screen triangle vertices (NDC coords + UV)
struct Vertex {
    float x, y;  // NDC position
    float u, v;  // UV
};

static const Vertex g_quad_vertices[] = {
    { -1.0f, -1.0f, 0.0f, 0.0f },
    {  3.0f, -1.0f, 2.0f, 0.0f },
    { -1.0f,  3.0f, 0.0f, 2.0f },
};

// D3D11 globals
static ID3D11Device*           g_device   = nullptr;
static ID3D11DeviceContext*    g_ctx      = nullptr;
static IDXGISwapChain*         g_swapchain = nullptr;
static IDXGIOutputDuplication* g_dupl     = nullptr;
static ID3D11Buffer*           g_vb       = nullptr;

static ID3D11Texture2D*          g_captured_tex  = nullptr;
static ID3D11ShaderResourceView* g_captured_srv  = nullptr;

// Intermediate render targets for multi-effect compositing (ping-pong)
static ID3D11Texture2D*          g_temp_tex[2]   = {nullptr, nullptr};
static ID3D11RenderTargetView*   g_temp_rtv[2]   = {nullptr, nullptr};
static ID3D11ShaderResourceView* g_temp_srv[2]   = {nullptr, nullptr};

static int g_width  = 0;
static int g_height = 0;

// ---- helper: create a texture + RTV + SRV that matches backbuffer ----
static bool create_intermediate_texture(int w, int h,
    ID3D11Texture2D** tex, ID3D11RenderTargetView** rtv, ID3D11ShaderResourceView** srv)
{
    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width  = w;
    desc.Height = h;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    HRESULT hr = g_device->CreateTexture2D(&desc, nullptr, tex);
    if (FAILED(hr)) return false;

    hr = g_device->CreateRenderTargetView(*tex, nullptr, rtv);
    if (FAILED(hr)) return false;

    hr = g_device->CreateShaderResourceView(*tex, nullptr, srv);
    if (FAILED(hr)) return false;

    return true;
}

static void release_intermediate_texture(
    ID3D11Texture2D*& tex, ID3D11RenderTargetView*& rtv, ID3D11ShaderResourceView*& srv)
{
    if (srv) srv->Release();
    if (rtv) rtv->Release();
    if (tex) tex->Release();
    tex = nullptr; rtv = nullptr; srv = nullptr;
}

// ---- public API ----

bool renderer_init(HWND hwnd) {
    g_width  = GetSystemMetrics(SM_CXSCREEN);
    g_height = GetSystemMetrics(SM_CYSCREEN);

    // --- Find the adapter driving the primary desktop ---
    IDXGIFactory1* factory = nullptr;
    CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void**)&factory);

    IDXGIAdapter1* chosen_adapter = nullptr;
    IDXGIOutput*   chosen_output  = nullptr;

    IDXGIAdapter1* adapter = nullptr;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; i++) {
        IDXGIOutput* output = nullptr;
        for (UINT j = 0; adapter->EnumOutputs(j, &output) != DXGI_ERROR_NOT_FOUND; j++) {
            DXGI_OUTPUT_DESC desc;
            output->GetDesc(&desc);
            if (desc.AttachedToDesktop) {
                chosen_adapter = adapter;
                chosen_adapter->AddRef();
                chosen_output = output;
                chosen_output->AddRef();
                output->Release();
                break;
            }
            output->Release();
        }
        adapter->Release();
        if (chosen_adapter) break;
    }
    factory->Release();

    if (!chosen_adapter || !chosen_output) return false;

    // --- Create D3D11 device ---
    D3D_FEATURE_LEVEL feature_level;
    UINT flags = 0;
#ifdef _DEBUG
    flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    HRESULT hr = D3D11CreateDevice(
        chosen_adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags,
        nullptr, 0, D3D11_SDK_VERSION,
        &g_device, &feature_level, &g_ctx
    );

    if (FAILED(hr)) {
        // Fallback: use default adapter
        hr = D3D11CreateDevice(
            nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
            nullptr, 0, D3D11_SDK_VERSION,
            &g_device, &feature_level, &g_ctx
        );
    }

    if (FAILED(hr)) return false;

    // --- Desktop Duplication ---
    IDXGIOutput1* output1 = nullptr;
    chosen_output->QueryInterface(__uuidof(IDXGIOutput1), (void**)&output1);
    if (output1) {
        output1->DuplicateOutput(g_device, &g_dupl);
        output1->Release();
    }
    chosen_output->Release();
    chosen_adapter->Release();

    if (!g_dupl) return false;

    // --- SwapChain ---
    DXGI_SWAP_CHAIN_DESC sc_desc = {};
    sc_desc.BufferCount = 1;
    sc_desc.BufferDesc.Width  = g_width;
    sc_desc.BufferDesc.Height = g_height;
    sc_desc.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sc_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sc_desc.OutputWindow = hwnd;
    sc_desc.SampleDesc.Count = 1;
    sc_desc.Windowed = TRUE;
    sc_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    IDXGIFactory1* swapchain_factory = nullptr;
    CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void**)&swapchain_factory);
    hr = swapchain_factory->CreateSwapChain(g_device, &sc_desc, &g_swapchain);
    swapchain_factory->Release();
    if (FAILED(hr)) return false;

    // --- Full-screen triangle vertex buffer ---
    D3D11_BUFFER_DESC vb_desc = {};
    vb_desc.ByteWidth = sizeof(g_quad_vertices);
    vb_desc.Usage = D3D11_USAGE_IMMUTABLE;
    vb_desc.BindFlags = D3D11_BIND_VERTEX_BUFFER;

    D3D11_SUBRESOURCE_DATA vb_data = { g_quad_vertices, 0, 0 };
    g_device->CreateBuffer(&vb_desc, &vb_data, &g_vb);

    // --- Render state ---
    UINT stride = sizeof(Vertex);
    UINT offset = 0;
    g_ctx->IASetVertexBuffers(0, 1, &g_vb, &stride, &offset);
    g_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    ID3D11VertexShader* vs = shader_get_builtin_vs(g_device);
    ID3D11InputLayout*  layout = shader_get_input_layout(g_device);
    g_ctx->VSSetShader(vs, nullptr, 0);
    g_ctx->IASetInputLayout(layout);

    D3D11_SAMPLER_DESC smp_desc = {};
    smp_desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    smp_desc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    smp_desc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    smp_desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    ID3D11SamplerState* sampler;
    g_device->CreateSamplerState(&smp_desc, &sampler);
    g_ctx->PSSetSamplers(0, 1, &sampler);
    sampler->Release(); // ref held by context

    // --- Intermediate textures for multi-effect compositing ---
    renderer_resize(g_width, g_height);

    return true;
}

void renderer_resize(int w, int h) {
    if (w == g_width && h == g_height) return;
    g_width = w; g_height = h;

    release_intermediate_texture(g_temp_tex[0], g_temp_rtv[0], g_temp_srv[0]);
    release_intermediate_texture(g_temp_tex[1], g_temp_rtv[1], g_temp_srv[1]);

    if (g_swapchain) {
        g_ctx->OMSetRenderTargets(0, nullptr, nullptr);
        g_swapchain->ResizeBuffers(1, w, h, DXGI_FORMAT_B8G8R8A8_UNORM, 0);
    }

    create_intermediate_texture(w, h, &g_temp_tex[0], &g_temp_rtv[0], &g_temp_srv[0]);
    create_intermediate_texture(w, h, &g_temp_tex[1], &g_temp_rtv[1], &g_temp_srv[1]);
}

void renderer_render_frame(const std::vector<Shader*>& active_shaders) {
    if (!g_dupl || !g_ctx) return;

    // --- Acquire desktop frame ---
    IDXGIResource* desktop_resource = nullptr;
    DXGI_OUTDUPL_FRAME_INFO frame_info;
    HRESULT hr = g_dupl->AcquireNextFrame(16, &frame_info, &desktop_resource);

    if (hr == DXGI_ERROR_ACCESS_LOST) {
        // Recreate duplication on lost access (e.g., UAC prompt, Ctrl+Alt+Del)
        g_dupl->Release(); g_dupl = nullptr;
        // Re-init from stored output... for v1 just ignore this frame
        return;
    }
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) return;
    if (FAILED(hr)) return;

    // Get the desktop texture
    if (g_captured_tex) { g_captured_tex->Release(); g_captured_tex = nullptr; }
    if (g_captured_srv) { g_captured_srv->Release(); g_captured_srv = nullptr; }

    hr = desktop_resource->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&g_captured_tex);
    desktop_resource->Release();
    if (FAILED(hr)) { g_dupl->ReleaseFrame(); return; }

    D3D11_TEXTURE2D_DESC tex_desc;
    g_captured_tex->GetDesc(&tex_desc);

    D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc = {};
    srv_desc.Format = tex_desc.Format;
    srv_desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srv_desc.Texture2D.MipLevels = 1;
    g_device->CreateShaderResourceView(g_captured_tex, &srv_desc, &g_captured_srv);

    // --- Multi-effect compositing with ping-pong ---
    int N = (int)active_shaders.size();
    if (N == 0) {
        g_dupl->ReleaseFrame();
        return;
    }

    ID3D11RenderTargetView* backbuffer_rtv = nullptr;
    ID3D11Texture2D* backbuffer_tex = nullptr;
    g_swapchain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&backbuffer_tex);
    g_device->CreateRenderTargetView(backbuffer_tex, nullptr, &backbuffer_rtv);
    backbuffer_tex->Release();

    ID3D11ShaderResourceView* src_srv = g_captured_srv;
    int dst_idx = 0;

    for (int i = 0; i < N; i++) {
        bool is_last = (i == N - 1);

        if (N == 1) {
            // Single effect: render directly to backbuffer
            g_ctx->OMSetRenderTargets(1, &backbuffer_rtv, nullptr);
        } else if (is_last) {
            // Last of multiple: render to backbuffer
            g_ctx->OMSetRenderTargets(1, &backbuffer_rtv, nullptr);
            src_srv = g_temp_srv[1 - dst_idx]; // previous pass output
        } else if (i == 0) {
            // First pass: capture → temp[dst_idx]
            g_ctx->OMSetRenderTargets(1, &g_temp_rtv[dst_idx], nullptr);
        } else {
            // Middle pass: temp[prev] → temp[dst_idx]
            g_ctx->OMSetRenderTargets(1, &g_temp_rtv[dst_idx], nullptr);
            src_srv = g_temp_srv[1 - dst_idx];
        }

        g_ctx->PSSetShader(active_shaders[i]->ps, nullptr, 0);
        g_ctx->PSSetShaderResources(0, 1, &src_srv);
        g_ctx->PSSetConstantBuffers(0, 1, &active_shaders[i]->cbuffer);
        g_ctx->Draw(3, 0);

        if (N > 1 && i == 0) {
            src_srv = g_temp_srv[dst_idx];
            dst_idx = 1 - dst_idx;
        }
    }

    // --- Present ---
    g_swapchain->Present(1, 0); // VSync on

    backbuffer_rtv->Release();
    g_dupl->ReleaseFrame();
}

void renderer_shutdown() {
    release_intermediate_texture(g_temp_tex[0], g_temp_rtv[0], g_temp_srv[0]);
    release_intermediate_texture(g_temp_tex[1], g_temp_rtv[1], g_temp_srv[1]);
    if (g_captured_srv) g_captured_srv->Release();
    if (g_captured_tex) g_captured_tex->Release();
    if (g_vb) g_vb->Release();
    if (g_dupl) g_dupl->Release();
    if (g_swapchain) g_swapchain->Release();
    if (g_ctx) g_ctx->Release();
    if (g_device) g_device->Release();
}

ID3D11Device*        renderer_get_device()    { return g_device; }
ID3D11DeviceContext* renderer_get_context()   { return g_ctx; }
int renderer_width()  { return g_width; }
int renderer_height() { return g_height; }
```

- [ ] **Step 3: Verify compilation**

```bash
cmake --build build --config Release
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/d3d11_renderer.h src/d3d11_renderer.cpp
git commit -m "feat: D3D11 renderer with Desktop Duplication and multi-effect compositing"
```

---

### Task 7: Effect Shader Files

**Files:**
- Create: `shaders/invert.hlsl`
- Create: `shaders/magnifier.hlsl`
- Create: `shaders/warm_color.hlsl`

Each .hlsl file contains ONLY the pixel shader `main()` function. The cbuffer, textures, and PS_INPUT struct are prepended by shader_manager at compile time.

- [ ] **Step 1: Write `shaders/invert.hlsl`**

```hlsl
float4 main(PS_INPUT input) : SV_TARGET {
    float4 color = u_scene.Sample(u_sampler, input.uv);
    color.rgb = 1.0 - color.rgb;
    return color;
}
```

- [ ] **Step 2: Write `shaders/magnifier.hlsl`**

```hlsl
float4 main(PS_INPUT input) : SV_TARGET {
    float2 mouse_uv = u_mouse / u_resolution;
    float2 delta = input.uv - mouse_uv;
    float dist = length(delta * float2(u_resolution.x / u_resolution.y, 1.0));
    float radius_uv = u_param_radius / u_resolution.x;

    if (dist < radius_uv) {
        float t = 1.0 - smoothstep(0.0, radius_uv, dist);
        float zoom = lerp(1.0, u_param_zoom, t);
        float2 sample_uv = mouse_uv + delta / zoom;
        return u_scene.Sample(u_sampler, sample_uv);
    }

    return u_scene.Sample(u_sampler, input.uv);
}
```

- [ ] **Step 3: Write `shaders/warm_color.hlsl`**

```hlsl
// Temperature range: ~1000K (warm/red) to ~12000K (cool/blue)
// Reference white point adjustments via RGB gain

float3 temperature_to_gain(float temp_k) {
    // Clamp to range
    temp_k = clamp(temp_k, 1000.0, 12000.0);
    // Normalize 0..1 where 0=warm, 1=cool, 0.5=neutral (6500K)
    float t = (temp_k - 6500.0) / 6500.0;

    // Warm shift: boost red, reduce blue
    // Cool shift: boost blue, reduce red
    float3 warm = float3(1.15, 0.85, 0.65);
    float3 cool = float3(0.65, 0.85, 1.15);
    float3 neutral = float3(1.0, 1.0, 1.0);

    if (t < 0.0) return lerp(neutral, warm, -t);
    else         return lerp(neutral, cool,  t);
}

float4 main(PS_INPUT input) : SV_TARGET {
    float4 color = u_scene.Sample(u_sampler, input.uv);
    float3 gain = temperature_to_gain(u_param_temperature);
    color.rgb *= gain;
    return color;
}
```

- [ ] **Step 4: Verify compilation**

The shader files are not compiled by CMake — they are compiled at runtime. To verify they parse correctly, we'll test via the full app in Task 8. For now, just confirm the files exist.

```bash
ls d:/my_project_for_D/Mirage/shaders/
```

Expected: `invert.hlsl`, `magnifier.hlsl`, `warm_color.hlsl` exist.

- [ ] **Step 5: Commit**

```bash
git add shaders/invert.hlsl shaders/magnifier.hlsl shaders/warm_color.hlsl
git commit -m "feat: three v1 shader effects (invert, magnifier, warm_color)"
```

---

### Task 8: Main Integration

**Files:**
- Modify: `src/main.cpp` (replace skeleton)

**What this task does:** Wires all modules together in WinMain. The message loop drives everything: pumps Windows messages, updates input state, manages effect activation/deactivation, runs the render loop, handles F5 config reload.

- [ ] **Step 1: Rewrite `src/main.cpp`**

```cpp
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <d3d11.h>
#include <chrono>
#include <string>
#include <vector>
#include <unordered_map>

#include "config_manager.h"
#include "overlay_window.h"
#include "input_manager.h"
#include "shader_manager.h"
#include "d3d11_renderer.h"

static Config                    g_config;
static HWND                      g_hwnd = nullptr;
static std::vector<Shader*>      g_shaders;
static std::vector<EffectConfig> g_effects;
static bool                      g_running = true;
static bool                      g_overlay_visible = false;

// Timer for effect elapsed time
static LARGE_INTEGER g_freq;
static std::vector<float> g_effect_start_times;

static std::string get_exe_dir() {
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring ws(path);
    std::string s(ws.begin(), ws.end());
    size_t pos = s.find_last_of("\\/");
    return s.substr(0, pos + 1);
}

static void load_all_shaders() {
    // Unload old
    for (auto* s : g_shaders) shader_unload(s);
    g_shaders.clear();

    ID3D11Device* device = renderer_get_device();
    for (const auto& cfg : g_config.effects) {
        std::string full_path = get_exe_dir() + cfg.shader_path;
        EffectConfig cfg_with_path = cfg;
        cfg_with_path.shader_path = full_path;

        Shader* s = shader_load(device, cfg_with_path);
        if (s) {
            g_shaders.push_back(s);
        } else {
            // Mark as failed — push null so indices stay aligned
            g_shaders.push_back(nullptr);
        }
    }

    g_effects = g_config.effects;
}

static void update_and_render() {
    // Update input state machine
    input_update(g_effects);

    // Check for F5 reload
    if (input_should_reload()) {
        input_clear_reload_flag();
        g_config = load_config(get_exe_dir() + "config.json");
        load_all_shaders();
    }

    // Collect active effects (by pointer to EffectConfig + Shader pair)
    const auto& active = input_effect_active_states();
    std::vector<Shader*> active_shaders;
    for (size_t i = 0; i < active.size() && i < g_shaders.size(); i++) {
        if (active[i] && g_shaders[i]) {
            active_shaders.push_back(g_shaders[i]);
        }
    }

    // Manage overlay window visibility
    if (!active_shaders.empty() && !g_overlay_visible) {
        ShowWindow(g_hwnd, SW_SHOW);
        g_overlay_visible = true;
    } else if (active_shaders.empty() && g_overlay_visible) {
        ShowWindow(g_hwnd, SW_HIDE);
        g_overlay_visible = false;
    }

    if (!g_overlay_visible) return;

    // Update shader uniforms
    float mx = input_mouse_x();
    float my = input_mouse_y();
    float dt = input_time_delta();

    static float total_time = 0.0f;
    total_time += dt;

    ID3D11DeviceContext* ctx = renderer_get_context();
    for (size_t i = 0; i < active_shaders.size(); i++) {
        shader_update_cbuffer(ctx, active_shaders[i],
            mx, my, total_time, dt,
            renderer_width(), renderer_height());
    }

    // Render
    renderer_render_frame(active_shaders);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int nCmdShow) {
    QueryPerformanceFrequency(&g_freq);

    // Load config
    g_config = load_config(get_exe_dir() + "config.json");

    // Create overlay window
    int sw, sh;
    get_screen_size(sw, sh);
    g_hwnd = create_overlay_window(hInstance, sw, sh);
    if (!g_hwnd) return -1;

    // Init renderer
    if (!renderer_init(g_hwnd)) {
        destroy_overlay_window(g_hwnd);
        return -1;
    }

    // Init input
    input_init();

    // Load shaders
    load_all_shaders();

    // Initially hidden — shown when first effect activates
    ShowWindow(g_hwnd, SW_HIDE);

    // Message loop
    MSG msg = {};
    while (g_running) {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                g_running = false;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        update_and_render();

        // Throttle when idle
        if (!g_overlay_visible) {
            Sleep(16); // ~60fps polling for hotkey detection
        }
    }

    // Shutdown
    input_shutdown();
    for (auto* s : g_shaders) shader_unload(s);
    renderer_shutdown();
    destroy_overlay_window(g_hwnd);

    return 0;
}
```

- [ ] **Step 2: Build and verify**

```bash
cmake --build build --config Release
```

Expected: Build succeeds with zero errors.

- [ ] **Step 3: Manual smoke test plan**

Prepare: Copy the built `mirage.exe` to a directory alongside `config.json` and the `shaders/` folder.

Run `mirage.exe` (double-click or from terminal):
- Nothing visible should happen (no window, no console)
- Press `Ctrl+Shift+I` — screen should invert colors
- Press `Ctrl+Shift+I` again — screen should return to normal
- Press `Ctrl+Shift+M` — a magnifier should appear around cursor while held; release to stop
- Press `Ctrl+Shift+W` — screen should take on warm color temperature; press again to remove
- Press `F5` — config should reload (no visible change if config unchanged)
- No window should be in taskbar; clicks should pass through to underlying windows

- [ ] **Step 4: Commit**

```bash
git add src/main.cpp
git commit -m "feat: wire main integration with message loop and hot reload"
```
