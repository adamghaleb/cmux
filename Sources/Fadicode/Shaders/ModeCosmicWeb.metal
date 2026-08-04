#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Cosmic Web: dark matter filament structure connecting galaxy clusters

[[ stitchable ]]
half4 cosmicWebEffect(
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

    // Voronoi-based filament structure at multiple scales
    float filaments = 0.0;

    for (int layer = 0; layer < 3; layer++) {
        float fl = float(layer);
        float scale = 3.0 + fl * 2.0;
        float2 lp = p * scale + float2(fl * 5.3, fl * 3.7);

        float2 cellId = floor(lp);
        float2 cellUv = fract(lp);

        float minDist1 = 10.0;
        float minDist2 = 10.0;

        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float2 neighbor = float2(float(dx), float(dy));
                float2 id = cellId + neighbor;
                float2 rnd = hash22(id);
                float2 point = neighbor + rnd + 0.1 * sin(t * 0.5 + rnd * 6.28);
                float d = length(cellUv - point);
                if (d < minDist1) { minDist2 = minDist1; minDist1 = d; }
                else if (d < minDist2) { minDist2 = d; }
            }
        }

        // Filaments form at cell boundaries (where minDist2 - minDist1 is small)
        float edge = smoothstep(0.15, 0.0, minDist2 - minDist1);
        // Nodes form at cell vertices (where minDist1 is very small)
        float node = smoothstep(0.15, 0.0, minDist1);

        float weight = 1.0 / (1.0 + fl);
        filaments += (edge * 0.6 + node * 0.4) * weight;
    }

    // Pulsing nodes (galaxy clusters)
    float pulse = sin(t * 1.5 + filaments * 5.0) * 0.15;

    // Background: deep space FBM
    float nebula = fbm(p * 2.0, t * 0.2) * 0.5 + 0.5;

    float lum = filaments + pulse + nebula * 0.08;
    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
