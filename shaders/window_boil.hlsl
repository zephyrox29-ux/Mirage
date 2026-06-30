// Window Boil — windows boil like water with soft edges, desktop stays still
// Params: intensity (default 1.0), speed (default 1.0)

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

// Signed distance to rectangle interior (negative inside, positive outside)
float rect_sdf(float2 p, float2 rmin, float2 rmax) {
    float2 c = (rmin + rmax) * 0.5;
    float2 h = (rmax - rmin) * 0.5;
    float2 d = abs(p - c) - h;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv     = input.uv;
    float intens  = u_param_intensity > 0.0 ? u_param_intensity : 1.0;
    float spd     = u_param_speed     > 0.0 ? u_param_speed     : 1.0;
    float t       = u_time * spd * 8.0;

    float4 orig   = u_scene.Sample(u_sampler, uv);
    float4 boiled = orig;

    // Find nearest window and compute soft blend
    float best_inside = -1.0;    // how far inside a window (negative SDF)
    float2 best_rmin, best_rmax;
    bool   found = false;

    for (uint i = 0; i < min(u_window_count, 64u); i++) {
        float4 r    = u_window_rects[i];
        float2 rmin = r.xy / u_resolution;
        float2 rmax = r.zw / u_resolution;

        float sdf = rect_sdf(uv, rmin, rmax);
        if (sdf < best_inside || !found) {
            best_inside = sdf;
            best_rmin   = rmin;
            best_rmax   = rmax;
            found       = true;
        }
    }

    if (found) {
        // Soft blend zone: full boil inside, fade to normal over ~3% of screen
        float blend_zone = 0.02; // UV units of soft transition
        float blend = 1.0 - smoothstep(-blend_zone, blend_zone, best_inside);

        if (blend > 0.001 && best_inside < blend_zone) {
            float2 local = (uv - best_rmin) / max(best_rmax - best_rmin, 0.001);

            // Multi-octave boiling noise
            float n1 = noise2d(local * 30.0 + float2(t * 2.3, t * 1.7));
            float n2 = noise2d(local * 60.0 + float2(t * 3.1, -t * 2.5)) * 0.5;
            float n3 = noise2d(local * 120.0 + float2(-t * 1.9, t * 3.7)) * 0.25;

            float2 displace;
            displace.x = (n1 * 0.04 + n2 * 0.02 + n3 * 0.01) * intens;
            displace.y = (noise2d(local * 25.0 + float2(t * 1.5, t * 2.9)) * 0.04
                       + noise2d(local * 55.0 + float2(-t * 2.7, t * 1.3)) * 0.02) * intens;

            float2 duv = clamp(uv + displace, best_rmin + 0.002, best_rmax - 0.002);
            float4 boil_sample = u_scene.Sample(u_sampler, duv);

            // Depth darkening near edges
            float edge_dist = min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y));
            float edge_fade = smoothstep(0.0, 0.06, edge_dist);
            boil_sample.rgb *= lerp(0.88, 1.0, edge_fade);

            boiled = boil_sample;
        }

        orig.rgb = lerp(orig.rgb, boiled.rgb, blend);
    }

    return orig;
}
