#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Folding Dimensions: surfaces that fold into impossible non-Euclidean configurations

[[ stitchable ]]
half4 foldingDimensionsEffect(
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
    float2 p = s.centered;

    // Iterative folding: abs() creates mirror symmetry, rotation breaks it
    float2 z = p * 2.5;
    float lum = 0.0;

    for (int i = 0; i < 7; i++) {
        float fi = float(i);

        // Fold
        z = abs(z) - 0.8 + 0.1 * sin(t * 0.3 + fi);

        // Rotate
        float angle = t * 0.12 + fi * 0.4;
        float ca = cos(angle), sa = sin(angle);
        z = float2(z.x * ca - z.y * sa, z.x * sa + z.y * ca);

        // Scale down
        z *= 1.2;

        // Accumulate: distance from fold edges creates structure
        float foldDist = min(abs(z.x), abs(z.y));
        lum += smoothstep(0.1, 0.0, foldDist) / (1.0 + fi * 0.4);
    }

    // Add glow at fold intersections
    float intersect = smoothstep(0.2, 0.0, length(fract(z * 0.5) - 0.5));
    lum += intersect * 0.2;

    // Breathing scale modulation
    float breathe = sin(t * 0.5) * 0.15;
    lum *= (1.0 + breathe);

    // Soft center glow
    lum += smoothstep(0.4, 0.0, s.dist) * 0.15;

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
