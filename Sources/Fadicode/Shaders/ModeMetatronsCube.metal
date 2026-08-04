#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Metatron's Cube: 13 circles of the Fruit of Life with connecting lines
// forming all 5 Platonic solids projected onto 2D. Multiple rotation layers,
// sacred patterns within each circle, FBM organic breath.

[[ stitchable ]]
half4 metatronsCubeEffect(
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

    float lum = 0.0;

    // --- Build the 13 circle centers of the Fruit of Life ---
    // Center + 6 inner ring + 6 outer ring
    float2 centers[13];
    float circleR = 0.28 + 0.015 * sin(t * 0.6);

    // Center circle
    centers[0] = float2(0.0, 0.0);

    // Inner ring: 6 circles at distance = circleR
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * M_PI_F / 3.0 + t * 0.08;
        centers[i + 1] = float2(cos(angle), sin(angle)) * circleR;
    }

    // Outer ring: 6 circles at distance = circleR * sqrt(3), offset by 30 degrees
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * M_PI_F / 3.0 + M_PI_F / 6.0 + t * 0.06;
        centers[i + 7] = float2(cos(angle), sin(angle)) * circleR * 1.732;
    }

    // --- Draw the 13 circles ---
    float circles = 0.0;
    float innerPatterns = 0.0;

    for (int i = 0; i < 13; i++) {
        float fi = float(i);
        float d = length(p - centers[i]);
        float phase = hash21(float2(fi, fi * 1.7)) * 6.28;

        // Circle outline: crisp smoothstep ring
        float ringWidth = 0.008 + 0.003 * sin(t * 0.4 + phase);
        float ring = smoothstep(ringWidth, 0.0, abs(d - circleR * 0.5));
        circles += ring;

        // Sacred pattern inside each circle: rotating star geometry
        if (d < circleR * 0.48) {
            float innerAngle = atan2(p.y - centers[i].y, p.x - centers[i].x);
            float innerR = d / (circleR * 0.5);

            // Rotating geometry: triangle morphing to hexagon per circle
            float sides = 3.0 + floor(fi * 0.5);
            float rotSpeed = t * (0.3 + fi * 0.05) + phase;
            float shapeAngle = innerAngle + rotSpeed;
            float shape = cos(M_PI_F / sides) / cos(fmod(shapeAngle + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);

            // Internal star pattern
            float star = smoothstep(0.02, 0.0, abs(innerR - shape * 0.6));
            star += smoothstep(0.02, 0.0, abs(innerR - shape * 0.3));

            // Radial spokes inside
            float spokes = sin(innerAngle * sides + rotSpeed * 2.0) * 0.5 + 0.5;
            spokes *= smoothstep(circleR * 0.5, circleR * 0.1, d);

            innerPatterns += (star * 0.5 + spokes * 0.15) * smoothstep(circleR * 0.5, circleR * 0.35, d);
        }
    }

    // --- Connecting lines: all 78 connections between the 13 circles ---
    // (forming the complete Metatron's Cube with all Platonic solid projections)
    float lines = 0.0;
    for (int i = 0; i < 13; i++) {
        for (int j = i + 1; j < 13; j++) {
            float2 a = centers[i];
            float2 b = centers[j];

            // Point-to-line-segment distance
            float2 ab = b - a;
            float tParam = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
            float2 closest = a + ab * tParam;
            float lineDist = length(p - closest);

            // Line thickness varies by connection type
            float pairDist = length(a - b);
            float lineThick = 0.004;
            if (pairDist < circleR * 1.1) lineThick = 0.006; // Inner connections thicker

            // Energy pulse along the line
            float fi = float(i);
            float fj = float(j);
            float pulse = sin(tParam * 12.0 - t * 2.0 + fi * 0.3 + fj * 0.7) * 0.4 + 0.6;

            float line = smoothstep(lineThick, 0.0, lineDist) * pulse;
            lines += line * 0.15;
        }
    }

    // --- Outer bounding circle (the containment sphere) ---
    float outerR = circleR * 2.1;
    float outerRing = smoothstep(0.01, 0.0, abs(length(p) - outerR));
    float outerRing2 = smoothstep(0.006, 0.0, abs(length(p) - outerR * 1.08));

    // --- Platonic solid highlight layer ---
    // Rotating hexagonal overlay suggesting the cube projection
    float2 rp = float2(
        p.x * cos(t * 0.12) - p.y * sin(t * 0.12),
        p.x * sin(t * 0.12) + p.y * cos(t * 0.12)
    );
    float hexOverlay = cos(atan2(rp.y, rp.x) * 6.0) * 0.5 + 0.5;
    hexOverlay *= smoothstep(outerR, circleR * 0.8, length(p));
    hexOverlay *= smoothstep(circleR * 0.2, circleR * 0.5, length(p));

    // Second rotation layer: triangle projection at different speed
    float2 rp2 = float2(
        p.x * cos(-t * 0.18) - p.y * sin(-t * 0.18),
        p.x * sin(-t * 0.18) + p.y * cos(-t * 0.18)
    );
    float triOverlay = cos(atan2(rp2.y, rp2.x) * 3.0) * 0.5 + 0.5;
    triOverlay *= smoothstep(outerR, circleR * 0.5, length(p));

    // --- FBM organic breath modulation ---
    float breath = fbm(p * 2.0, t * 0.3);
    float breathMod = 0.85 + breath * 0.2;

    // --- Combine all layers ---
    lum = circles * 0.35
        + innerPatterns * 0.25
        + lines
        + outerRing * 0.3
        + outerRing2 * 0.15
        + hexOverlay * 0.12
        + triOverlay * 0.08;

    lum *= breathMod;

    // Soft center glow
    lum += smoothstep(0.3, 0.0, s.dist) * 0.1;

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
