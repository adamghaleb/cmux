#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Lava Lamp: metaball-like blobby organic shapes drifting and merging

[[ stitchable ]]
half4 lavaLampEffect(
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

    // Metaball field: sum of inverse-distance contributions
    float field = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float2 blobCenter = float2(
            sin(t * (0.3 + fi * 0.07) + fi * 2.1) * 0.8,
            cos(t * (0.25 + fi * 0.05) + fi * 1.7) * 0.8
        );
        float radius = 0.2 + 0.1 * sin(t * 0.4 + fi * 1.5);
        float d = length(p - blobCenter);
        field += (radius * radius) / (d * d + 0.01);
    }

    // Threshold the field for blob shapes
    float blobs = smoothstep(0.8, 1.5, field);

    // Add internal texture via fbm
    float texture = fbm(p * 2.0 + float2(t * 0.15), t * 0.5);
    texture = texture * 0.5 + 0.5;

    float lum = blobs * 0.7 + blobs * texture * 0.3;

    // Ambient warmth in the background
    lum += smoothstep(2.0, 0.0, s.dist) * 0.08;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
