#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Flower of Life: full Flower of Life with Metatron's Cube overlay, breathing

[[ stitchable ]]
half4 flowerOfLifeEffect(
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
    float t = time * 0.2;
    float2 p = s.centered;

    float lum = 0.0;

    // Breathing radius
    float breathe = 1.0 + 0.06 * sin(t * 0.5);
    float circleR = 0.2 * breathe;
    float lineWidth = 0.006;

    // Flower of Life: 19 overlapping circles
    // Center circle
    float d0 = abs(length(p) - circleR);
    lum += smoothstep(lineWidth * 2.0, 0.0, d0) * 0.3;

    // First ring: 6 circles
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + t * 0.05;
        float2 center = float2(cos(a), sin(a)) * circleR;
        float d = abs(length(p - center) - circleR);
        lum += smoothstep(lineWidth * 2.0, 0.0, d) * 0.25;
    }

    // Second ring: 6 circles at double distance
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + t * 0.05;
        float2 center = float2(cos(a), sin(a)) * circleR * 2.0;
        float d = abs(length(p - center) - circleR);
        lum += smoothstep(lineWidth * 2.0, 0.0, d) * 0.2;
    }

    // Third ring: 6 circles between second ring positions
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + M_PI_F / 6.0 + t * 0.05;
        float2 center = float2(cos(a), sin(a)) * circleR * 1.732; // sqrt(3)
        float d = abs(length(p - center) - circleR);
        lum += smoothstep(lineWidth * 2.0, 0.0, d) * 0.2;
    }

    // Metatron's Cube: 13 nodes connected by lines
    float2 metaNodes[13];
    metaNodes[0] = float2(0.0, 0.0);

    // Inner hexagon
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + t * 0.08;
        metaNodes[i + 1] = float2(cos(a), sin(a)) * circleR;
    }

    // Outer hexagon
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + t * 0.08;
        metaNodes[i + 7] = float2(cos(a), sin(a)) * circleR * 2.0;
    }

    // Draw all connections in Metatron's Cube
    for (int i = 0; i < 13; i++) {
        for (int j = i + 1; j < 13; j++) {
            float2 a2 = metaNodes[i];
            float2 b2 = metaNodes[j];
            float2 ab = b2 - a2;
            float len = length(ab);
            if (len < 0.001) continue;
            float2 dir = ab / len;
            float tParam = clamp(dot(p - a2, dir), 0.0, len);
            float2 closest = a2 + dir * tParam;
            float d = length(p - closest);

            // Pulsing energy along the line
            float energy = sin(tParam / len * 8.0 - t * 2.0 + float(i + j) * 0.3) * 0.3 + 0.7;
            float line = smoothstep(lineWidth, 0.0, d) * energy;
            lum += line * 0.04;
        }
    }

    // Node glow at each Metatron vertex
    for (int i = 0; i < 13; i++) {
        float d = length(p - metaNodes[i]);
        float pulse = sin(t * 1.2 + float(i) * 0.48) * 0.25 + 0.75;
        lum += smoothstep(0.02, 0.0, d) * 0.2 * pulse;
    }

    // Seed of Life highlight: the 7 center circles glow brighter
    float seedGlow = smoothstep(circleR * 2.5, circleR * 0.5, length(p));
    seedGlow *= sin(t * 0.8) * 0.1 + 0.1;
    lum += seedGlow;

    // Vesica Piscis intersection highlights
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + t * 0.05;
        float2 center = float2(cos(a), sin(a)) * circleR;
        float d1 = length(p);
        float d2 = length(p - center);
        // Vesica: inside both circles
        if (d1 < circleR * 1.05 && d2 < circleR * 1.05) {
            float vesica = smoothstep(circleR * 1.05, circleR * 0.8, max(d1, d2));
            lum += vesica * 0.03 * (sin(t * 1.5 + float(i)) * 0.5 + 0.5);
        }
    }

    // Outer bounding circle
    float outerR = circleR * 3.0;
    float outerCircle = abs(length(p) - outerR);
    lum += smoothstep(lineWidth * 3.0, 0.0, outerCircle) * 0.15;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
