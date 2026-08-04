#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Moire: interference patterns from overlapping wave grids at different angles

[[ stitchable ]]
half4 moireEffect(
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

    // Layer 1: horizontal lines, slowly drifting
    float freq = 20.0;
    float lines1 = sin(p.y * freq + t * 2.0) * 0.5 + 0.5;

    // Layer 2: rotated lines (slight angle creates moire)
    float angle2 = t * 0.15;
    float2 rot2 = float2(
        p.x * cos(angle2) - p.y * sin(angle2),
        p.x * sin(angle2) + p.y * cos(angle2)
    );
    float lines2 = sin(rot2.y * freq * 0.95) * 0.5 + 0.5;

    // Layer 3: concentric circles
    float circles = sin(s.dist * freq * 0.8 - t * 1.5) * 0.5 + 0.5;

    // Layer 4: diagonal grid at different angle
    float angle4 = M_PI_F / 3.0 + t * 0.1;
    float2 rot4 = float2(
        p.x * cos(angle4) - p.y * sin(angle4),
        p.x * sin(angle4) + p.y * cos(angle4)
    );
    float lines4 = sin(rot4.y * freq * 1.05) * 0.5 + 0.5;

    // Interference: multiply overlapping patterns
    float moire = lines1 * lines2 * 0.5 + circles * lines4 * 0.5;

    // Boost contrast of the interference pattern
    moire = smoothstep(0.1, 0.4, moire);

    float lum = moire;
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
