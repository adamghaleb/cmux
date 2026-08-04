#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 gradientSpinEffect(
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

    float t = time * 0.3; // slowed from raw time
    float aspect = viewWidth / viewHeight;
    float2 rp = s.uv * 2.0 - 1.0;
    rp.x *= aspect;
    float wrappedTime = fmod(t, 2.0 * M_PI_F);
    float angle = atan2(rp.y, rp.x) + wrappedTime;
    float3 rgb = float3(abs(sin(angle)), abs(sin(angle + 2.0)), abs(sin(angle + 4.0)));
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
