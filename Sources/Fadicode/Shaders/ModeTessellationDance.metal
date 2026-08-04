#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Tessellation Dance: animated Penrose-inspired impossible tiling

[[ stitchable ]]
half4 tessellationDanceEffect(
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

    float t = time * 0.2;
    float2 p = s.centered;

    // Create 5-fold quasi-crystal tiling (Penrose-like)
    // Overlay 5 sets of parallel lines at 72-degree angles
    float pattern = 0.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float angle = fi * M_PI_F / 5.0 + t * 0.05;
        float2 dir = float2(cos(angle), sin(angle));
        float proj = dot(p * 5.0, dir) + t * 0.3 * (fmod(fi, 2.0) - 0.5);

        // Create line pattern along this direction
        float lines = fract(proj);
        float edge = smoothstep(0.05, 0.0, lines) + smoothstep(0.95, 1.0, lines);

        // Tile fill brightness varies per cell
        float cellId = floor(proj);
        float brightness = hash21(float2(cellId, fi)) * 0.5 + 0.25;
        float fill = brightness * smoothstep(0.05, 0.15, lines) * smoothstep(0.95, 0.85, lines);

        pattern += edge * 0.15 + fill * 0.1;
    }

    // Highlight pentagons: where multiple line intersections coincide
    // Use the product of all 5 line patterns
    float pentHighlight = 1.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float angle = fi * M_PI_F / 5.0 + t * 0.05;
        float2 dir = float2(cos(angle), sin(angle));
        float proj = dot(p * 5.0, dir);
        float cell = fract(proj);
        pentHighlight *= smoothstep(0.0, 0.3, cell) * smoothstep(1.0, 0.7, cell);
    }
    pattern += (1.0 - pentHighlight) * 0.2;

    // Breathing modulation
    float breathe = sin(t * 0.6) * 0.1 + 1.0;
    pattern *= breathe;

    // Subtle FBM overlay for organic feel
    float organic = fbm(p * 2.5, t * 0.3) * 0.5 + 0.5;
    pattern *= (0.8 + organic * 0.3);

    float lum = pattern;
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
