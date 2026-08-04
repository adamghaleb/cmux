#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 auroraEffect(
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
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float yOffset = -0.3 + fi * 0.2;
        float wave = simplex2d(float2(s.centered.x * 2.0 + fi * 0.7, time * 0.25 + fi * 1.3));
        float ribbon = smoothstep(0.15, 0.0, abs(s.centered.y - yOffset - wave * 0.4));
        ribbon *= smoothstep(1.5, 0.0, abs(s.centered.x));
        lum += ribbon * 0.5;
    }
    float shimmer = simplex2d(float2(s.uv.x * 30.0, time * 0.5));
    lum += max(shimmer, 0.0) * 0.08;
    lum += smoothstep(1.2, 0.0, s.dist) * 0.1;
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
