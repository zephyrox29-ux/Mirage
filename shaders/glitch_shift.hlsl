// Glitch Shift — screen-split glitch art: right half shifts with mouse Y + noise
// RGB channel splitting, scanlines, random "crashes"
// Params: shift_amount (default 1.0), glitch_speed (default 1.0)

float hash21(float2 p) {
    p = frac(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return frac(p.x * p.y);
}

float noise1d(float x) {
    float i = floor(x);
    float f = frac(x);
    return lerp(hash21(float2(i, 0.0)), hash21(float2(i + 1.0, 0.0)), f * f * (3.0 - 2.0 * f));
}

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv     = input.uv;
    float  amount = u_param_shift_amount > 0.0 ? u_param_shift_amount : 1.0;
    float  speed  = u_param_glitch_speed  > 0.0 ? u_param_glitch_speed  : 1.0;
    float  t      = u_time * speed;

    // Split screen at random-ish position that wobbles
    float split_x = 0.48 + sin(t * 0.7) * 0.02 + hash21(float2(floor(t * 0.5), 0.0)) * 0.04;

    if (uv.x < split_x) {
        // Left half: mostly normal, subtle scanlines
        float4 c = u_scene.Sample(u_sampler, uv);
        float scanline = sin(uv.y * u_resolution.y * 0.7) * 0.03 + 0.97;
        c.rgb *= scanline;
        return c;
    }

    // Right half: glitched

    // Block-based noise displacement
    float block_size = lerp(40.0, 200.0, noise1d(t * 0.3));
    float block_id = floor(uv.y * u_resolution.y / block_size);
    float block_noise = hash21(float2(block_id, floor(t * 2.0)));

    // Shift amount varies per block
    float shift_y = (u_mouse.y / u_resolution.y - 0.5) * 0.15 * amount;
    float shift_x = (block_noise - 0.5) * 0.12 * amount;

    // Some blocks are more glitched than others
    float corrupt = step(0.3, block_noise);

    // RGB split
    float r_shift = shift_x * (1.0 + corrupt * 3.0);
    float g_shift = shift_x * (1.0 + corrupt * 0.5);
    float b_shift = shift_x * (1.0 + corrupt * 2.0);

    float2 r_uv = clamp(float2(uv.x + r_shift, uv.y + shift_y * 1.2), 0.001, 0.999);
    float2 g_uv = clamp(float2(uv.x + g_shift, uv.y), 0.001, 0.999);
    float2 b_uv = clamp(float2(uv.x + b_shift, uv.y - shift_y * 0.8), 0.001, 0.999);

    float r = u_scene.Sample(u_sampler, r_uv).r;
    float g = u_scene.Sample(u_sampler, g_uv).g;
    float b = u_scene.Sample(u_sampler, b_uv).b;

    // Random blocks get color inversion or brightness boost
    if (corrupt > 0.5) {
        float block_corrupt = hash21(float2(block_id, 1.0));
        if (block_corrupt > 0.7) {
            r = 1.0 - r;
            g = 1.0 - g;
            b = 1.0 - b;
        }
    }

    float3 color = float3(r, g, b);

    // Horizontal shift lines (like bad VHS tracking)
    float line_noise = noise1d(uv.y * 80.0 + t * 5.0);
    if (line_noise > 0.85) {
        float line_shift = (line_noise - 0.85) * 0.3 * amount;
        color = lerp(color, float3(0.2, 0.1, 0.3), line_shift * 3.0);
    }

    // Scan lines
    float scanline = sin(uv.y * u_resolution.y * 0.5 + t * 2.0) * 0.04 + 0.96;
    color *= scanline;

    // Occasional full-screen "crash" flicker
    float crash = step(0.97, hash21(float2(floor(t * 3.0), 42.0)));
    color = lerp(color, float3(0.0, 0.0, 0.0), crash * 0.7);

    return float4(color, 1.0);
}
