#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Plasma: classic overlapping sine waves creating smooth organic gradients

[[ stitchable ]]
half4 plasmaEffect(
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

    // Classic plasma: overlapping sine functions at different scales
    float v1 = sin(p.x * 3.0 + t);
    float v2 = sin(p.y * 3.0 + t * 0.7);
    float v3 = sin((p.x + p.y) * 2.0 + t * 1.3);
    float v4 = sin(length(p - float2(sin(t * 0.5), cos(t * 0.6))) * 4.0);
    float v5 = sin(length(p + float2(cos(t * 0.3), sin(t * 0.4))) * 3.0);

    float plasma = (v1 + v2 + v3 + v4 + v5) / 5.0;
    plasma = plasma * 0.5 + 0.5;

    // Add subtle fbm for organic texture
    float organic = simplex2d(p * 2.0 + float2(t * 0.2, t * 0.15));
    organic = organic * 0.5 + 0.5;

    float lum = plasma * 0.75 + organic * 0.25;
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
