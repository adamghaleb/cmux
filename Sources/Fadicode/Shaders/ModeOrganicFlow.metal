#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 organicFlowEffect(
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
    float flow1 = fbm(s.centered * 1.2, t);
    float flow2 = fbm(s.centered * 1.5 + float2(3.7, 1.3), t * 1.3);
    float flow = flow1 * 0.6 + flow2 * 0.4;
    flow = flow * 0.5 + 0.5;
    float lum = flow * 0.8;
    lum *= smoothstep(1.6, 0.2, s.dist);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
