// Kaleidoscope — 8-sector kaleidoscope centered on mouse
// Window areas preserved as original; outside windows → mirrored kaleidoscope
// Params: sector_count (default 8), rotation_speed (default 0.5)

static const float PI = 3.14159265;

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv     = input.uv;
    float2 m_uv   = u_mouse / u_resolution;
    float2 delta  = uv - m_uv;
    float  radius = length(delta);
    float  angle  = atan2(delta.y, delta.x);

    float sectors = u_param_sector_count > 0.0 ? u_param_sector_count : 8.0;
    float rot_spd = u_param_rotation_speed > 0.0 ? u_param_rotation_speed : 0.5;
    float slice   = 2.0 * PI / sectors;
    float half    = slice * 0.5;

    // Rotate with time
    angle += u_time * rot_spd;

    // Mirror within sector
    float a = fmod(angle, slice);
    if (a > half) a = slice - a;

    float2 suv = m_uv + float2(cos(a), sin(a)) * radius;

    // Clamp to screen
    suv = clamp(suv, 0.001, 0.999);

    float4 color = u_scene.Sample(u_sampler, suv);

    // Preserve window interiors as original
    for (uint i = 0; i < min(u_window_count, 64u); i++) {
        float4 r = u_window_rects[i];
        float2 rmin = r.xy / u_resolution;
        float2 rmax = r.zw / u_resolution;
        if (uv.x >= rmin.x && uv.x <= rmax.x &&
            uv.y >= rmin.y && uv.y <= rmax.y) {
            return u_scene.Sample(u_sampler, uv);
        }
    }

    // Subtle vignette at edges
    float vignette = 1.0 - smoothstep(0.4, 1.2, radius) * 0.3;
    color.rgb *= vignette;

    return color;
}
