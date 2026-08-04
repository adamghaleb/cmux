#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Improved: bigger particles with soft glow halos for better posterization

[[ stitchable ]]
half4 pointCloudEffect(
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

    float lum = 0.0;
    float aspect = viewWidth / viewHeight;
    float2 auv = float2(s.uv.x * aspect, s.uv.y);

    // Primary layer: large glowing orbs
    float2 grid1 = auv * 8.0;
    float2 cellId1 = floor(grid1);
    float2 cellUv1 = fract(grid1);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId1 + neighbor;
            float2 rnd = hash22(id);
            float2 pos = neighbor + rnd + 0.2 * sin(time * 0.3 + rnd * 6.28);
            float d = length(cellUv1 - pos);
            float bright = hash21(id + 0.5);
            float pulse = sin(time * (0.3 + bright) + bright * 6.28) * 0.5 + 0.5;
            // Soft outer glow
            lum += smoothstep(0.5, 0.0, d) * bright * pulse * 0.35;
            // Bright core
            lum += smoothstep(0.2, 0.0, d) * bright * pulse * 0.6;
            // Hot center
            lum += smoothstep(0.08, 0.0, d) * bright * pulse * 0.4;
        }
    }

    // Secondary layer: medium scattered dots
    float2 grid2 = auv * 14.0;
    float2 cellId2 = floor(grid2);
    float2 cellUv2 = fract(grid2);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId2 + neighbor;
            float2 rnd = hash22(id + 50.0);
            float2 pos = neighbor + rnd + 0.15 * sin(time * 0.25 + rnd * 6.28);
            float d = length(cellUv2 - pos);
            float bright = hash21(id + 50.5);
            float pulse = sin(time * 0.3 + bright * 6.28) * 0.5 + 0.5;
            lum += smoothstep(0.3, 0.0, d) * bright * pulse * 0.3;
            lum += smoothstep(0.1, 0.0, d) * bright * pulse * 0.25;
        }
    }

    // Ambient glow from center
    lum += smoothstep(1.5, 0.0, s.dist) * 0.08;

    lum *= smoothstep(1.5, 0.3, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
