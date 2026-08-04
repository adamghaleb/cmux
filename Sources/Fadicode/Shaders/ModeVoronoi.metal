#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Voronoi: organic cell structure like stained glass or cracked earth

[[ stitchable ]]
half4 voronoiEffect(
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

    float t = time * 0.25;
    float2 p = s.centered * 3.0;

    // Voronoi distance field
    float2 cellId = floor(p);
    float2 cellUv = fract(p);

    float minDist = 10.0;
    float secondDist = 10.0;
    float cellBright = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId + neighbor;
            float2 rnd = hash22(id);
            // Animate cell centers slowly
            float2 point = neighbor + rnd + 0.3 * sin(t + rnd * 6.28);
            float d = length(cellUv - point);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
                cellBright = hash21(id);
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }

    // Edge detection: bright edges where cells meet
    float edge = smoothstep(0.0, 0.12, secondDist - minDist);

    // Cell fill: each cell gets a brightness from its hash
    float cellFill = cellBright * 0.6 + 0.2;

    // Combine: bright edges + varying cell fills
    float lum = (1.0 - edge) * 0.8 + cellFill * edge;

    // Pulsing glow based on cell brightness
    lum += (1.0 - edge) * 0.15 * sin(t * 2.0 + cellBright * 6.28);

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
