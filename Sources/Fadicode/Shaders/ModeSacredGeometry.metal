#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Sacred Geometry: flower of life + rotating hexagonal patterns

[[ stitchable ]]
half4 sacredGeometryEffect(
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

    // Flower of Life: overlapping circles arranged in hex grid
    float flower = 0.0;
    float circleRadius = 0.4 + 0.05 * sin(t);

    // Central circle
    flower += smoothstep(0.02, 0.0, abs(length(p) - circleRadius));

    // 6 surrounding circles (first ring)
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * M_PI_F / 3.0 + t * 0.15;
        float2 center = float2(cos(angle), sin(angle)) * circleRadius;
        flower += smoothstep(0.02, 0.0, abs(length(p - center) - circleRadius));
    }

    // 6 more circles (second ring, offset)
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * M_PI_F / 3.0 + M_PI_F / 6.0 + t * 0.1;
        float2 center = float2(cos(angle), sin(angle)) * circleRadius * 1.73;
        flower += smoothstep(0.015, 0.0, abs(length(p - center) - circleRadius));
    }

    // Hexagonal grid overlay
    float hexAngle = atan2(p.y, p.x);
    float hex6 = sin(hexAngle * 6.0 - t * 0.5) * 0.5 + 0.5;
    float hex12 = sin(hexAngle * 12.0 + t * 0.3) * 0.5 + 0.5;

    // Radial waves
    float radial = sin(s.dist * 10.0 - t * 2.0) * 0.5 + 0.5;

    float lum = flower * 0.4 + hex6 * radial * 0.3 + hex12 * 0.15;

    // Soft glow from intersections
    lum += smoothstep(0.8, 0.0, s.dist) * flower * 0.15;

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
