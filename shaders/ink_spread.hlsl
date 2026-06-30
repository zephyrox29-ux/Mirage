// Ink Spread — expanding ink blobs that turn covered area B&W high-contrast
// Ink spawns from window positions in repeating cycles
// Params: ink_speed (default 1.0), contrast (default 1.0), blob_count (default 8.0)

float hash21(float2 p) {
    p = frac(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return frac(p.x * p.y);
}

float noise2d(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(hash21(i), hash21(i + float2(1.0, 0.0)), f.x),
        lerp(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), f.x),
        f.y);
}

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv    = input.uv;
    float speed  = u_param_ink_speed  > 0.0 ? u_param_ink_speed  : 1.0;
    float contr  = u_param_contrast   > 0.0 ? u_param_contrast   : 1.0;
    float count  = u_param_blob_count > 0.0 ? u_param_blob_count : 8.0;
    float t      = u_time * speed;

    float4 color = u_scene.Sample(u_sampler, uv);
    float ink = 0.0;

    // Ink blobs from window positions
    int blob_n = int(count);
    int source_count = int(min(u_window_count, 64u));
    if (source_count < 1) source_count = 8;

    for (int b = 0; b < blob_n; b++) {
        // Pick a source window index (cycles through windows)
        int src_idx = (b + int(floor(t * 0.4))) % source_count;
        float2 src_center;

        if (u_window_count > 0 && src_idx < int(u_window_count)) {
            float4 r = u_window_rects[src_idx];
            src_center = (r.xy + r.zw) * 0.5 / u_resolution;
        } else {
            // Fallback: random positions
            src_center = float2(
                hash21(float2(float(b) * 7.3, 0.0)),
                hash21(float2(float(b) * 13.7, 0.0)));
        }

        // Each blob has its own phase
        float phase = frac(t * 0.25 + float(b) / count);
        float radius = phase * 1.5; // expands over cycle

        // Distance from this blob center
        float dist = length(uv - src_center);

        // Ink edge: soft, slightly irregular
        float edge_noise = noise2d(uv * 250.0 + float(b) * 17.0) * 0.02;
        float ink_edge = smoothstep(radius + 0.015, radius - 0.05 + edge_noise, dist);

        // Fade in at start, fade out near end of cycle
        float life = smoothstep(0.0, 0.15, phase) * (1.0 - smoothstep(0.7, 1.0, phase));
        ink = max(ink, ink_edge * life);
    }

    // Covered by ink: B&W high contrast
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    float contrast_boost = 2.0 * contr;
    float hc = clamp((gray - 0.5) * contrast_boost + 0.5, 0.0, 1.0);
    float3 ink_color = float3(hc, hc, hc);

    // Add subtle blue-black tint in ink
    ink_color = lerp(ink_color, float3(hc * 0.15, hc * 0.12, hc * 0.18), 0.3);

    color.rgb = lerp(color.rgb, ink_color, ink);

    return color;
}
