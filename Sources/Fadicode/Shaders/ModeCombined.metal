#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 combinedEffect(
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
    float flow1 = fbm(s.centered * 1.2, t);
    float flow2 = fbm(s.centered * 1.5 + float2(3.7, 1.3), t * 1.3);
    float flow = flow1 * 0.6 + flow2 * 0.4;
    flow = flow * 0.5 + 0.5;

    float angle = atan2(s.centered.y, s.centered.x);
    float mandala = sin(angle * 6.0 + time * 0.3) * 0.5 + 0.5;
    float radialWave = sin(s.dist * 8.0 - time * 0.5) * 0.5 + 0.5;
    mandala *= radialWave * smoothstep(1.8, 0.2, s.dist);

    float aspect = viewWidth / viewHeight;
    float2 auv = float2(s.uv.x * aspect, s.uv.y);
    float2 pointGrid = auv * 12.0;
    float2 cellId = floor(pointGrid);
    float2 cellUv = fract(pointGrid);
    float points = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId + neighbor;
            float2 rnd = hash22(id);
            float2 pos = neighbor + rnd + 0.1 * sin(time * 0.3 + rnd * 6.28);
            float d = length(cellUv - pos);
            float bright = hash21(id + 0.5);
            float pulse = sin(time * (0.3 + bright) + bright * 6.28) * 0.5 + 0.5;
            points += smoothstep(0.25, 0.0, d) * bright * pulse;
        }
    }
    points = min(points, 1.0);

    float lum = flow * 0.4 + mandala * 0.25 + points * 0.35;
    float vignette = smoothstep(1.5, 0.3, s.dist);
    float edgeGlow = smoothstep(0.6, 1.3, s.dist) * (1.0 - smoothstep(1.3, 1.8, s.dist));
    lum += edgeGlow * 0.3;
    lum *= vignette;
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
