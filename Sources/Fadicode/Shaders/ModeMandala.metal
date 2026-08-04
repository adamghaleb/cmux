#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 mandalaEffect(
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

    float angle = atan2(s.centered.y, s.centered.x);
    float m6 = sin(angle * 6.0 + time * 0.3) * 0.5 + 0.5;
    float m12 = sin(angle * 12.0 - time * 0.2) * 0.5 + 0.5;
    float radial1 = sin(s.dist * 8.0 - time * 0.5) * 0.5 + 0.5;
    float radial2 = sin(s.dist * 14.0 + time * 0.3) * 0.5 + 0.5;
    float pattern = m6 * radial1 * 0.6 + m12 * radial2 * 0.4;
    pattern *= smoothstep(1.8, 0.1, s.dist);
    float ring = smoothstep(0.02, 0.0, abs(s.dist - 0.5 - 0.1 * sin(time * 0.4)));
    ring += smoothstep(0.015, 0.0, abs(s.dist - 0.8 - 0.05 * sin(time * 0.3)));
    float lum = clamp(pattern * 1.2 + ring * 0.6, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
