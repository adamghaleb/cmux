#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 lightGridEffect(
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

    float t = time * 0.4; // slowed from raw time
    float aspect = viewWidth / viewHeight;
    float2 auv = float2(s.uv.x * aspect, s.uv.y);
    float2 point = auv * 8.0;
    float2 nonRepeating = float2(12.9898, 78.233);
    float2 groupNumber = floor(point);
    float dotP = dot(groupNumber, nonRepeating);
    float sine = sin(dotP);
    float hugeNumber = sine * 43758.5453;
    float variance = (0.5 * sin(t + hugeNumber)) + 0.5;
    float acceleratedVariance = 3.0 * variance;

    float3 baseColor = float3(3.0, 1.5, 0.0);
    float3 variedColor = baseColor + acceleratedVariance + t;
    float3 variedColorSine = sin(variedColor);
    float3 newColor = (0.5 * variedColorSine) + 0.5;

    float2 adjustedGroupSize = M_PI_F * 2.0 * (point - 0.25);
    float2 groupSine = (0.5 * sin(adjustedGroupSize)) + 0.5;
    float2 pulse = smoothstep(float2(0.0), float2(1.0), groupSine);

    float3 rgb = newColor * pulse.x * pulse.y * 3.0;
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
