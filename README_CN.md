# Mirage

Windows 桌面屏幕着色器叠加层。通过透明全屏窗口对显示器画面实时应用 GPU 着色器效果（反色、放大镜、黑洞、暖色温、窗口边缘发光、窗口抖动等）。纯配置文件驱动，无界面。

- **< 500 KB** 可执行文件（静态 CRT）
- **60+ FPS**，集成显卡 1440p 下流畅运行
- **鼠标穿透** — 叠加层不拦截鼠标操作
- **窗口感知** — 着色器可获取屏幕上每个可见窗口的位置

![demo](demo.gif)

> [English README](README.md)

## 使用说明

### 系统要求

- Windows 10 或 11（64 位）
- 支持 DirectX 11 的显卡（集成或独立均可）

### 快速开始

1. 从 [Releases](https://github.com/lightarmmy/Mirage/releases) 页面下载 `Mirage.zip`
2. 解压得到 `mirage.exe`、`config.json` 和 `shaders/` 文件夹
3. 运行 `mirage.exe`（无需安装）

### 默认快捷键

| 快捷键 | 效果 |
|--------|------|
| `Ctrl+Shift+I` | 色彩反转（切换） |
| `Ctrl+Shift+M` | 万花筒（按住） |
| `Ctrl+Shift+W` | 窗口沸腾（切换） |
| `Ctrl+Shift+E` | 边缘霓虹（切换） |
| `Ctrl+Shift+J` | 错位空间（切换） |
| `Ctrl+Shift+K` | 墨水扩散（切换） |
| `Ctrl+Shift+B` | 黑洞效果（切换） |
| `F5` | 重新加载配置和着色器 |
| `Ctrl+Shift+D` | 导出窗口列表到 `桌面\mirage_debug.txt` |

### 自定义配置

编辑 `config.json` 可修改快捷键、增删效果或调整着色器参数。按 `F5` 即可热重载，无需重启程序。

**完整配置示例：**

```json
{
  "version": 1,
  "screensaver": {
    "enabled": true,
    "idle_seconds": 30,
    "effect": "blackhole"
  },
  "effects": [
    {
      "id": "invert",
      "name": "色彩反转",
      "shader": "shaders/invert.hlsl",
      "hotkey": { "keys": ["ctrl", "shift", "i"], "mode": "toggle" },
      "enabled": true
    },
    {
      "id": "blackhole",
      "name": "黑洞",
      "shader": "shaders/blackhole.hlsl",
      "hotkey": { "keys": ["ctrl", "shift", "b"], "mode": "toggle" },
      "params": {
        "hole_radius": 0.06,
        "fade": 1.0,
        "disk_gain": 2.2
      },
      "enabled": true
    }
  ]
}
```

**效果字段说明：**

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `id` | string | 必填 | 效果唯一标识 |
| `name` | string | `id` | 显示名称 |
| `shader` | string | 必填 | `.hlsl` 文件路径，相对于 `mirage.exe` |
| `hotkey.keys` | string[] | 必填 | 按键组合 |
| `hotkey.mode` | string | 必填 | 触发模式：`hold`、`toggle`、`oneshot`、`stack` |
| `params` | object | `{}` | 最多 16 个浮点键值对 |
| `enabled` | bool | `true` | 设为 `false` 可禁用效果但不从配置中删除 |

**触发模式：**
- `"hold"` — 按住按键时生效，松开即停止
- `"toggle"` — 按一次开启，再按一次关闭
- `"oneshot"` — 按一次触发，2 秒后自动关闭
- `"stack"` — 与 toggle 类似，多个效果可叠加

**可用按键：** `ctrl`、`shift`、`alt`、`win`、`a`–`z`、`0`–`9`、`f1`–`f12`、`space`、`tab`、`escape`、`enter`、`backspace`、`left`、`right`、`up`、`down`

### 屏保（自动空闲）

Mirage 可以在电脑无人操作时自动激活效果，类似屏保：

```json
"screensaver": {
  "enabled": true,
  "idle_seconds": 30,
  "effect": "blackhole"
}
```

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `enabled` | `false` | 设为 `true` 启用自动空闲激活 |
| `idle_seconds` | `30` | 无操作多少秒后触发 |
| `effect` | `"blackhole"` | 用作屏保的效果 ID |

空闲超时后，效果通过尺寸缩放平滑淡入（约 2 秒）。移动鼠标或按键后平滑淡出。手动快捷键可独立使用——在屏保激活时按下快捷键，即使恢复操作后效果也会保持；再次按下则关闭。

屏保效果必须包含 `fade` 参数（配置中设为 `1.0`）。程序通过此参数控制缩放动画——效果从零尺寸逐渐膨胀至完整状态，反之亦然。

### 着色器参数

每个效果最多可配置 16 个浮点参数。参数在着色器中通过 `u_param_<参数名>` 访问（如 `u_param_hole_radius`）。

### 常见问题

- **按下快捷键没有效果：** 查看桌面的 `mirage_shader_errors.txt`，里面记录了着色器编译错误。修正后按 `F5` 重载。
- **激活效果时短暂闪烁一下：** 这是正常的交换链预热，约 16ms（一帧），属于预期行为。
- **程序无法启动：** 请确保 `config.json` 和 `shaders/` 文件夹与 `mirage.exe` 在同一目录。

---

## 着色器制作指南

添加新效果只需两步：编写一个 HLSL 像素着色器文件并注册到配置文件。

### 快速示例：复古棕褐

**第一步，创建 `shaders/sepia.hlsl`：**

```hlsl
float4 main(PS_INPUT input) : SV_TARGET {
    float4 color = u_scene.Sample(u_sampler, input.uv);
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb = float3(gray + 0.15, gray + 0.07, gray - 0.12);
    return color;
}
```

**第二步，在 `config.json` 中注册：**

```json
{
  "id": "sepia",
  "name": "复古棕褐",
  "shader": "shaders/sepia.hlsl",
  "hotkey": { "keys": ["ctrl", "shift", "s"], "mode": "toggle" }
}
```

按 `F5`，完成。

### 可用输入

Mirage 会自动在每个着色器前面注入一段头文件声明，因此你可以直接使用以下变量，无需自行声明：

| 名称 | 类型 | 寄存器 | 说明 |
|------|------|--------|------|
| `u_resolution` | `float2` | cbuffer b0 | 屏幕分辨率（像素），如 (2560, 1440) |
| `u_mouse` | `float2` | cbuffer b0 | 鼠标光标位置（屏幕像素坐标） |
| `u_time` | `float` | cbuffer b0 | 程序运行总时间（秒），单调递增 |
| `u_time_delta` | `float` | cbuffer b0 | 帧间隔时间（秒） |
| `u_active_window` | `float4` | cbuffer b0 | 前台窗口矩形：(left, top, right, bottom)（像素） |
| `u_params[4]` | `float4[4]` | cbuffer b0 | 最多 16 个用户可配置浮点参数 |
| `u_window_count` | `uint` | cbuffer b0 | 屏幕上可见窗口数量（最多 64 个） |
| `u_window_rects[64]` | `float4[64]` | cbuffer b0 | 每个可见窗口的矩形：(left, top, right, bottom)（像素） |
| `u_scene` | `Texture2D` | t0 | 实时桌面截帧 |
| `u_sampler` | `SamplerState` | s0 | `u_scene` 的 Linear Clamp 采样器 |

入口函数签名必须为 `float4 main(PS_INPUT input) : SV_TARGET`，其中 `PS_INPUT` 提供 `float4 pos : SV_POSITION` 和 `float2 uv : TEXCOORD0`（UV 范围从左上角 (0,0) 到右下角 (1,1)）。

### 参数映射

`config.json` 中的参数会自动生成为 `#define` 宏。例如配置 `"params": { "intensity": 0.5, "speed": 3.0 }`，头文件将包含：

```hlsl
#define u_param_intensity u_params[0].x
#define u_param_speed     u_params[0].y
```

在着色器中直接使用 `u_param_intensity` 即可。参数按名称字母序排列，最多 16 个，依次占据 `u_params[0]` 到 `u_params[3]`。

一个常用惯例：在 `config.json` 中设置 `0.0` 表示"使用着色器内置默认值"：

```hlsl
float intensity = u_param_intensity > 0.0 ? u_param_intensity : 0.8; // 默认值 0.8
```

### 窗口感知效果

要制作与窗口位置交互的效果，使用 `u_window_rects`：

```hlsl
for (uint i = 0; i < u_window_count; i++) {
    float4 r = u_window_rects[i]; // (left, top, right, bottom) 像素坐标
    float2 win_min = r.xy / u_resolution;      // 转为 UV
    float2 win_max = r.zw / u_resolution;
    if (input.uv.x >= win_min.x && input.uv.x <= win_max.x &&
        input.uv.y >= win_min.y && input.uv.y <= win_max.y) {
        // 当前像素位于窗口 i 内部 — 在此处施加效果
    }
}
```

完整示例参见 `shaders/edge_glow.hlsl` 和 `shaders/window_jiggle.hlsl`。

### 着色器参考

| 文件 | 效果 | 关键技术 |
|------|------|---------|
| `invert.hlsl` | 色彩反转 | 最简着色器（一行代码） |
| `kaleidoscope.hlsl` | 鼠标万花筒（8 扇区） | 极坐标变换、扇区镜像、窗口保留 |
| `window_boil.hlsl` | 窗口沸腾 | 多层噪声、逐像素偏移 |
| `edge_neon.hlsl` | 扫描霓虹窗口边缘 + 光标火花 | 边缘距离、色相循环、接近检测 |
| `glitch_shift.hlsl` | 画面撕裂故障艺术 | RGB 通道分离、块噪声、VHS 扫描线 |
| `ink_spread.hlsl` | 墨迹扩散 → 黑白高对比 | 程序化墨点、生命周期动画、对比度增强 |
| `blackhole.hlsl` | 史瓦西黑洞 | 测地线光线追踪、吸积盘、黑体辐射 |

---

## 开发者指南

### 从源码构建

**环境要求：**
- Visual Studio 2022 BuildTools（或完整 VS 2022），需包含 C++ 工作负载
- Windows 10 SDK（10.0.22621 或更高）
- CMake 3.15+

```bash
# 在 Visual Studio Developer Command Prompt 中执行：
cd Mirage
cmake -B build -G "NMake Makefiles"
cmake --build build --config Release
```

输出文件为 `build\mirage.exe`。后置构建步骤会自动将 `config.json` 和 `shaders/` 复制到构建目录。

为方便起见，可使用 `build.bat` 一键构建（请参照自己的 VS 安装路径修改其中的 `vcvars64.bat` 路径）。

### 架构总览

```
mirage.exe
├── 叠加窗口             WS_EX_LAYERED + WS_EX_TRANSPARENT 全屏透明窗口
├── 桌面复制             IDXGIOutputDuplication 将桌面捕获为纹理
├── 交换链               DXGI_SWAP_EFFECT_FLIP_DISCARD，双缓冲
├── 着色器管理器         运行时编译 .hlsl 文件，管理常量缓冲区
├── 输入管理器           键盘钩子 + GetAsyncKeyState 热键检测
├── 配置管理器           通过 nlohmann/json 解析 JSON 配置
└── D3D11 渲染器         多效果乒乓合成、窗口枚举
```

**关键设计决策：**

- **双缓冲桌面副本** — `g_desktop_copy[2]` 配以乒乓索引。`CopyResource` 异步执行，GPU 同时读取上一份副本，避免同步停顿。
- **WDA_EXCLUDEFROMCAPTURE** — 叠加窗口被排除在桌面复制捕获之外，防止反馈循环。
- **自适应颜色格式** — 复制纹理延迟创建，在运行时精确匹配 DD 帧格式，对驱动差异具有鲁棒性。
- **Alpha 切换可见性** — 叠加窗口始终可见，通过切换 alpha=0（透明）和 alpha=255（不透明）来显示/隐藏效果，消除 swap chain 在 show/hide 时的残帧闪烁。
- **静态 CRT（`/MT`）** — 无运行时 DLL 依赖，单文件自包含可执行文件。

### 源文件地图

| 文件 | 职责 |
|------|------|
| `src/main.cpp` | WinMain 入口、消息循环、模块串联、F5 热重载、窗口导出 |
| `src/d3d11_renderer.h/cpp` | D3D11 设备初始化、桌面复制、交换链、帧合成、窗口枚举 |
| `src/shader_manager.h/cpp` | D3DCompile HLSL 编译、常量缓冲区创建、逐帧 cbuffer 更新 |
| `src/overlay_window.h/cpp` | 透明分层窗口创建、DPI 处理、WM_DISPLAYCHANGE |
| `src/input_manager.h/cpp` | WH_KEYBOARD_LL 钩子、GetAsyncKeyState 热键检测、4 种触发模式 |
| `src/config_manager.h/cpp` | JSON → C++ 配置解析、内置回退默认值 |
| `external/json.hpp` | nlohmann/json 单头文件库（v3.11） |

### 常量缓冲区布局

GPU 常量缓冲区（`MirageUniforms`，1152 字节，`#pragma pack 16`）必须与 `shader_manager.cpp:g_ps_header` 中的 HLSL cbuffer 声明一致。两者均定义于 `shader_manager.cpp`。

```
偏移    大小   字段
0       8      resolution[2]
8       8      mouse[2]
16      4      time
20      4      time_delta
24      8      _pad（对齐到 32）
32      16     active_window[4]
48      64     params[16]       ← 为黑洞效果从 4 扩展至 16
112     4      window_count
116     12     _pad2（对齐到 128）
128     1024   window_rects[64][4]
总计：1152
```

要添加新的 uniform 变量：同时修改 C++ 的 `MirageUniforms` 结构和 HLSL 的 `g_ps_header` 字符串。使用 `static_assert` 验证大小匹配。所有 `float4` 成员保持 16 字节对齐。

### 添加内置效果（回退默认值）

编辑 `config_manager.cpp` 中的 `build_defaults()` 函数。当 `config.json` 缺失或损坏时，将使用这些默认值。

### 渲染流程

```
每帧处理：
  1. input_update()          — 轮询热键，更新效果状态机
  2. AcquireNextFrame()      — 非阻塞（0ms 超时）DD 捕获
  3. CopyResource()          — 异步 GPU 复制到双缓冲
  4. shader_update_cbuffer() — 为每个活跃着色器填充常量缓冲区
  5. 对每个活跃着色器：
     - PSSetShaderResources  — 绑定桌面 SRV 到 t0
     - PSSetConstantBuffers  — 绑定着色器 cbuffer 到 b0
     - Draw(3, 0)            — 全屏三角形
     - 多效果？→ 乒乓中间渲染目标
  6. Present(1, 0)           — 垂直同步开启
```

### 发布打包

```bash
# 构建
cmake --build build --config Release

# 打包
mkdir release\Mirage
copy build\mirage.exe release\Mirage\
copy config.json release\Mirage\
xcopy shaders release\Mirage\shaders\ /E
# 将 release\Mirage\ 打包为 zip 即可分发
```

### 开发说明

本项目使用 **DeepSeek V4 Pro** 通过 **Claude Code** 作为 AI 编码助手协助开发。AI 参与了着色器移植、常量缓冲区设计、Bug 排查及文档编写。

### 第三方代码

黑洞着色器（`shaders/blackhole.hlsl`）改编自 [XboxNahida/ghostty-blackhole-main](https://github.com/XboxNahida/ghostty-blackhole-main)，MIT 许可证 — Copyright (c) 2025 XboxNahida。

### 许可证

MIT — 详见 [LICENSE](LICENSE)。
