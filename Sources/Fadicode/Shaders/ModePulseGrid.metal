#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 pulseGridEffect(
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

    float aspect = viewWidth / viewHeight;
    float2 auv = float2(s.uv.x * aspect, s.uv.y);
    float2 gridUv = auv * 20.0;
    float2 gridFrac = fract(gridUv);
    float lineX = smoothstep(0.06, 0.0, abs(gridFrac.x - 0.5));
    float lineY = smoothstep(0.06, 0.0, abs(gridFrac.y - 0.5));
    float grid = max(lineX, lineY);
    float pulse1 = smoothstep(0.06, 0.0, abs(fract(s.dist * 2.0 - time * 0.3) - 0.5));
    float pulse2 = smoothstep(0.04, 0.0, abs(fract(s.dist * 2.0 - time * 0.3 + 0.5) - 0.5));
    float intersect = lineX * lineY;
    float lum = grid * 0.25 + pulse1 * 0.5 + pulse2 * 0.3 + intersect * 0.15;
    float scanline = smoothstep(0.02, 0.0, abs(fract(auv.y * 3.0 - time * 0.15) - 0.5));
    lum += scanline * 0.2;
    lum *= smoothstep(1.8, 0.3, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
