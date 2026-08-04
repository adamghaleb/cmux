#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Hyperspace: non-Euclidean tunnel through impossible architecture

[[ stitchable ]]
half4 hyperspaceEffect(
    float2 position, half4 currentColor,
    float time, float intensity,
    float themeR, float themeG, float themeB,
    float viewWidth, float viewHeight,
    float pixelSize, float gridOpacity,
    float posterizeLevels,
    float hueSpread, float complementMix,
    float contrast,
    float brightness
) {
    if (intensity < 0.001) return half4(0.0h);
    PipelineSetup s = pipelineSetup(position, viewWidth, viewHeight, pixelSize, gridOpacity);

    float t = time * 0.3;
    float2 p = s.centered;
    float r = s.dist;
    float angle = atan2(p.y, p.x);

    // Tunnel: map to cylindrical coordinates
    float tunnel_depth = 1.0 / (r + 0.1);
    float tunnel_angle = angle;

    // Speed lines streaming toward viewer
    float speed = sin(tunnel_angle * 8.0 + tunnel_depth * 5.0 - t * 6.0) * 0.5 + 0.5;
    speed *= smoothstep(0.0, 0.3, r) * smoothstep(1.5, 0.2, r);

    // Non-Euclidean architecture: nested impossible shapes
    float arch = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float depth = fract(tunnel_depth * 0.3 - t * 0.4 + fi * 0.25);
        float scale = 1.0 / (depth + 0.3);

        // Rotating polygon at each depth
        float polyAngle = angle + t * 0.2 * (1.0 + fi * 0.3);
        float sides = 4.0 + fi * 2.0; // square, hex, octagon, decagon
        float polyDist = cos(M_PI_F / sides) / cos(fmod(polyAngle + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);
        float polyRing = abs(r * scale - polyDist * 0.5);
        arch += smoothstep(0.08, 0.0, polyRing) * depth * 0.4;
    }

    // FBM warp for organic feel
    float organic = fbm(float2(tunnel_angle * 2.0, tunnel_depth * 0.5), t * 0.4);
    organic = organic * 0.5 + 0.5;

    // Radial streaks (breakthrough effect)
    float streaks = sin(angle * 16.0 + t) * 0.5 + 0.5;
    streaks *= smoothstep(0.5, 0.0, r) * 0.3;

    float lum = speed * 0.3 + arch + organic * 0.2 + streaks;

    // Central white-out (approaching the void)
    lum += smoothstep(0.2, 0.0, r) * 0.4 * (sin(t * 1.5) * 0.3 + 0.7);

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
