// Kaleidoscope — multi-directional mirrored kaleidoscope centered on mouse
// Params: sectors (default 12.0), mirrors (default 3.0), speed (default 0.3)

static const float PI = 3.14159265;

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv      = input.uv;
    float2 m_uv    = u_mouse / u_resolution;
    float2 delta   = uv - m_uv;
    float  radius  = length(delta);
    float  angle   = atan2(delta.y, delta.x);

    float count   = u_param_sectors > 0.0 ? u_param_sectors : 12.0;
    float mirrors = u_param_mirrors > 0.0 ? u_param_mirrors : 3.0;
    float spd     = u_param_speed   > 0.0 ? u_param_speed   : 0.3;

    float slice   = 2.0 * PI / count;
    float half    = slice * 0.5;
    float rot     = u_time * spd;
    float a       = angle + rot;

    // Multiple mirroring passes for complex kaleidoscope patterns
    float  mir_a  = a;
    float  scale  = 1.0;

    for (float m = 0.0; m < mirrors; m += 1.0) {
        // Mirror within current sector
        float sa = fmod(mir_a, slice);
        if (sa > half) sa = slice - sa;

        // Alternate: reflect across sector boundaries differently each pass
        float pass_sectors = count * (1.0 + m * 0.5);
        float pass_slice   = 2.0 * PI / pass_sectors;
        float pass_half    = pass_slice * 0.5;
        float pa = fmod(a + m * 1.7, pass_slice);
        if (pa > pass_half) pa = pass_slice - pa;

        // Remap mirrored angle back to sample angle
        mir_a = lerp(sa, pa, 0.3 + m * 0.2);
        scale *= (1.05 - m * 0.08);
    }

    float2 suv = m_uv + float2(cos(mir_a), sin(mir_a)) * radius;
    suv = clamp(suv, 0.001, 0.999);

    float4 color = u_scene.Sample(u_sampler, suv);

    // Subtle vignette toward edges
    float vignette = 1.0 - smoothstep(0.5, 1.4, radius) * 0.25;
    color.rgb *= vignette;

    // Subtle color enhancement for more psychedelic feel
    float3 hsv = color.rgb;
    float gray = dot(hsv, float3(0.299, 0.587, 0.114));
    hsv = lerp(hsv, hsv * 1.15, 0.3);
    color.rgb = hsv;

    return color;
}
