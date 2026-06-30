// Edge Neon — scanning neon bands on window edges, cursor sparks
// Params: neon_width (default 8.0), speed (default 2.0), spark (default 1.0)

float hash21(float2 p) {
    p = frac(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return frac(p.x * p.y);
}

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv   = input.uv;
    float2 m_uv = u_mouse / u_resolution;
    float t     = u_time;

    float width = u_param_neon_width > 0.0 ? u_param_neon_width : 8.0;
    float speed = u_param_speed       > 0.0 ? u_param_speed       : 2.0;
    float spark = u_param_spark       > 0.0 ? u_param_spark       : 1.0;

    float4 color = u_scene.Sample(u_sampler, uv);
    float3 glow  = float3(0.0, 0.0, 0.0);

    for (uint w = 0; w < min(u_window_count, 64u); w++) {
        float4 r    = u_window_rects[w];
        float2 rmin = r.xy / u_resolution;
        float2 rmax = r.zw / u_resolution;

        // Skip tiny or off-screen windows
        float win_w = rmax.x - rmin.x;
        float win_h = rmax.y - rmin.y;
        if (win_w < 0.01 || win_h < 0.01) continue;

        // Distance to each edge (in UV)
        float d_left   = abs(uv.x - rmin.x);
        float d_right  = abs(uv.x - rmax.x);
        float d_top    = abs(uv.y - rmin.y);
        float d_bottom = abs(uv.y - rmax.y);

        float edge_d = min(min(d_left, d_right), min(d_top, d_bottom));
        float edge_px = edge_d * u_resolution.x;

        // Four edges have scanning neon bands
        float scan[4];
        float phase = w * 0.73 + t * speed;
        scan[0] = abs(frac((uv.y - rmin.y) / max(win_h, 0.001) * 3.0 + phase) - 0.5) * 2.0; // left
        scan[1] = abs(frac((uv.y - rmin.y) / max(win_h, 0.001) * 3.0 + phase + 0.5) - 0.5) * 2.0; // right
        scan[2] = abs(frac((uv.x - rmin.x) / max(win_w, 0.001) * 3.0 + phase + 0.25) - 0.5) * 2.0; // top
        scan[3] = abs(frac((uv.x - rmin.x) / max(win_w, 0.001) * 3.0 + phase + 0.75) - 0.5) * 2.0; // bottom

        float best_scan = max(max(scan[0], scan[1]), max(scan[2], scan[3]));
        float scan_mask = 1.0 - best_scan; // dark where scan band is, bright at edges of band

        // Neon glow: bright at window edge, fading outward
        float edge_glow = exp(-edge_px / width) * 1.5;

        // Scanning band modulation
        float band = exp(-scan_mask * scan_mask * 8.0) * 0.7 + 0.3;

        // Color cycles with time
        float3 neon_color;
        float hue = frac(phase * 0.1 + float(w) * 0.33);
        neon_color.r = sin(hue * 2.0 * 3.14159) * 0.5 + 0.5;
        neon_color.g = sin((hue + 0.33) * 2.0 * 3.14159) * 0.5 + 0.5;
        neon_color.b = sin((hue + 0.67) * 2.0 * 3.14159) * 0.5 + 0.5;
        neon_color = neon_color * 0.6 + 0.4; // pastel tint

        glow += neon_color * edge_glow * band * 0.6;
    }

    // Cursor proximity sparks
    for (uint s = 0; s < min(u_window_count, 64u); s++) {
        float4 r    = u_window_rects[s];
        float2 rmin = r.xy / u_resolution;
        float2 rmax = r.zw / u_resolution;

        // Mouse near this window's edge?
        float d_edges = 999.0;
        if (m_uv.x >= rmin.x && m_uv.x <= rmax.x) {
            d_edges = min(abs(m_uv.y - rmin.y), abs(m_uv.y - rmax.y));
        }
        if (m_uv.y >= rmin.y && m_uv.y <= rmax.y) {
            d_edges = min(d_edges, min(abs(m_uv.x - rmin.x), abs(m_uv.x - rmax.x)));
        }
        float mouse_near = smoothstep(0.08, 0.0, d_edges);

        if (mouse_near > 0.0) {
            // Spark from cursor position
            float spark_dist = length(uv - m_uv);
            float spark_radius = 0.02 + mouse_near * 0.06;
            float spark_glow = exp(-spark_dist / spark_radius) * mouse_near * spark * 3.0;

            // Random sparkle
            float sp = hash21(float2(floor(spark_dist * 200.0 + t * 30.0), s));
            float flicker = step(0.6, sp) * (sp - 0.6) * 2.5;

            glow += float3(1.0, 0.85, 0.4) * spark_glow * (1.0 + flicker * 2.0);
        }
    }

    // Composite glow additively
    color.rgb = color.rgb * 0.7 + glow;
    return color;
}
