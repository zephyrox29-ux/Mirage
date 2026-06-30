#include "config_manager.h"
#include <fstream>
#include <json.hpp>

using json = nlohmann::json;

static Config build_defaults() {
    Config c;
    c.version = 1;
    c.screensaver.enabled = false;
    c.screensaver.idle_seconds = 30;
    c.screensaver.effect_id = "blackhole";
    c.effects = {
        {
            "invert", "Color Inversion", "shaders/invert.hlsl", "toggle",
            {"ctrl", "shift", "i"}, {}
        },
        {
            "kaleidoscope", "Kaleidoscope", "shaders/kaleidoscope.hlsl", "hold",
            {"ctrl", "shift", "m"}, {{"mirrors", 3.0f}, {"sectors", 12.0f}, {"speed", 0.3f}}
        },
        {
            "window_boil", "Window Boil", "shaders/window_boil.hlsl", "toggle",
            {"ctrl", "shift", "w"}, {{"intensity", 1.0f}, {"speed", 1.0f}}
        },
        {
            "edge_neon", "Edge Neon", "shaders/edge_neon.hlsl", "toggle",
            {"ctrl", "shift", "e"}, {{"neon_width", 8.0f}, {"speed", 2.0f}, {"spark", 1.0f}}
        },
        {
            "glitch_shift", "Glitch Shift", "shaders/glitch_shift.hlsl", "toggle",
            {"ctrl", "shift", "j"}, {{"shift_amount", 1.0f}, {"glitch_speed", 1.0f}}
        },
        {
            "ink_spread", "Ink Spread", "shaders/ink_spread.hlsl", "toggle",
            {"ctrl", "shift", "k"}, {{"ink_speed", 1.0f}, {"contrast", 1.0f}, {"blob_count", 8.0f}}
        },
        {
            "blackhole", "Black Hole", "shaders/blackhole.hlsl", "toggle",
            {"ctrl", "shift", "b"},
            {{"center_drift", 1.0f}, {"hole_radius", 0.06f}, {"disk_gain", 2.2f}, {"disk_temp", 5500.0f},
             {"exposure", 1.4f}, {"fade", 1.0f}, {"disk_speed", 5.0f}, {"star_gain", 0.3f},
             {"disk_incl", 1.5f}, {"disk_inner", 0.0f}, {"disk_outer", 0.0f},
             {"disk_opacity", 0.0f}, {"doppler_mix", 0.6f}, {"disk_beam", 0.0f},
             {"disk_contrast", 0.0f}, {"disk_wind", 0.0f}, {"disk_roll", 0.0f}}
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
        c.exclude_from_capture = j.value("exclude_from_capture", true);

        for (const auto& ej : j.at("effects")) {
            EffectConfig ec;
            ec.id = ej.at("id").get<std::string>();
            ec.name = ej.value("name", ec.id);
            ec.shader_path = ej.at("shader").get<std::string>();
            ec.enabled = ej.value("enabled", true);

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

        if (j.contains("screensaver")) {
            const auto& ss = j.at("screensaver");
            c.screensaver.enabled = ss.value("enabled", false);
            c.screensaver.idle_seconds = ss.value("idle_seconds", 30);
            c.screensaver.effect_id = ss.value("effect", "blackhole");
        }

        return c;
    } catch (...) {
        return build_defaults();
    }
}
