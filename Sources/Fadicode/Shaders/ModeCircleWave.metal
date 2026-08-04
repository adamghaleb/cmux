#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 circleWaveEffect(
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

    float t = time * 0.3; // massively slowed from time * 20
    float2 delta = s.uv - 0.5;
    float aspectRatio = viewWidth / viewHeight;
    delta.x *= aspectRatio;
    float pixelDistance = length(delta);
    float waveSpeed = -(t * 10.0);
    float colorStrength = pow(1.0 - pixelDistance, 3.0) * 1.5;
    float waveDensity = 40.0 * pixelDistance;
    float cosine = cos(waveSpeed + waveDensity);
    float cosineAdjustment = (0.5 * cosine) + 0.5;
    float lum = colorStrength * (1.5 + cosineAdjustment);
    lum *= 1.0 - (pixelDistance * 2.0);
    lum = max(0.0, lum);
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
