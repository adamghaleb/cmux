#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Ripple Pond: concentric ripples from multiple animated sources

[[ stitchable ]]
half4 ripplePondEffect(
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

    // Multiple ripple sources that drift slowly
    float lum = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 center = float2(
            sin(t * 0.3 + fi * 1.3) * 0.6,
            cos(t * 0.25 + fi * 1.7) * 0.6
        );
        float d = length(s.centered - center);
        float ripple = sin(d * 15.0 - t * 4.0 + fi * 1.2) * 0.5 + 0.5;
        // Ripples fade with distance from source
        ripple *= smoothstep(1.5, 0.0, d);
        // Each source has different strength
        float strength = 0.3 - fi * 0.03;
        lum += ripple * strength;
    }

    // Interference creates natural-looking wave patterns
    // Add subtle surface texture
    float surface = simplex2d(s.centered * 4.0 + float2(t * 0.1, t * 0.15));
    lum += surface * 0.06;

    lum *= smoothstep(1.8, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
