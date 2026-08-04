#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Ego Dissolution: boundaries dissolve into infinite recursive expansion

[[ stitchable ]]
half4 egoDissolutionEffect(
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
    float r = s.dist;

    // Recursive zoom: multiple scales overlaid
    float lum = 0.0;
    float totalWeight = 0.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float scale = pow(2.0, fi) * (1.0 + 0.2 * sin(t * 0.3 + fi));
        float rotation = t * 0.15 * (1.0 + fi * 0.2);

        float2 rp = float2(
            p.x * cos(rotation) - p.y * sin(rotation),
            p.x * sin(rotation) + p.y * cos(rotation)
        );
        rp *= scale;

        // Organic boundary pattern at this scale
        float n = simplex2d(rp + float2(t * 0.1, fi * 3.7));
        float boundary = smoothstep(0.0, 0.3, abs(n));

        // Dissolving edges: thin bright lines where boundaries break
        float dissolve = (1.0 - boundary) * smoothstep(0.0, 0.02, abs(n));

        float weight = 1.0 / (1.0 + fi * 0.5);
        lum += dissolve * weight;
        totalWeight += weight;
    }

    lum /= totalWeight;

    // Breathing expansion: radial pulse
    float breathe = sin(t * 0.8) * 0.1;
    float expansion = smoothstep(0.8 + breathe, 0.0, r) * 0.3;

    // Deep void opening at center
    float voidGlow = smoothstep(0.3, 0.0, r) * 0.4;
    voidGlow *= (sin(t * 1.2) * 0.2 + 0.8);

    // Outer boundary: where self meets infinity
    float outerRing = smoothstep(0.03, 0.0, abs(r - 0.8 - breathe * 2.0));
    outerRing *= 0.3;

    // FBM organic wash
    float wash = fbm(p * 2.0 + float2(t * 0.15), t * 0.4);
    wash = wash * 0.5 + 0.5;

    lum = lum * 0.5 + expansion + voidGlow + outerRing + wash * 0.1;
    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
