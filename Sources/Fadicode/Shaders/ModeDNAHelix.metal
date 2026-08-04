#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// DNA Helix: double helix spiral with molecular glow, full 3D rotation

[[ stitchable ]]
half4 dnaHelixEffect(
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
    float2 p = s.centered;

    float lum = 0.0;

    // 3D rotation: the entire helix rotates around Y axis
    float rotY = t * 0.8; // slow continuous Y spin
    float cosR = cos(rotY);
    float sinR = sin(rotY);

    // Also tilt slightly on X axis for more 3D feel
    float tiltX = sin(t * 0.2) * 0.3;
    float cosT = cos(tiltX);
    float sinT = sin(tiltX);

    // Helix parameters — bigger, bolder
    float helixRadius = 0.35;
    float pitch = 4.0;

    // Sample multiple Y slices for volumetric feel
    for (int slice = -2; slice <= 2; slice++) {
        float yOff = float(slice) * 0.02;
        float y = (p.y + yOff) * pitch;

        // Two strands, 180 degrees apart
        for (int strand = 0; strand < 2; strand++) {
            float offset = float(strand) * M_PI_F;

            // 3D helix point before rotation
            float hx = cos(y + t * 2.5 + offset) * helixRadius;
            float hz = sin(y + t * 2.5 + offset) * helixRadius;
            float hy = p.y + yOff;

            // Apply Y rotation (spin around vertical axis)
            float rx = hx * cosR - hz * sinR;
            float rz = hx * sinR + hz * cosR;

            // Apply X tilt
            float ry2 = hy * cosT - rz * sinT;
            float rz2 = hy * sinT + rz * cosT;

            // Depth: rz2 controls brightness (front bright, back dim)
            float depth = rz2 * 1.2 + 0.7;
            depth = clamp(depth, 0.15, 1.0);

            // Project to 2D
            float projX = rx;
            float dx = p.x - projX;

            // Strand rendering — thicker with stronger glow
            float strandWidth = 0.04 * depth;
            float outerGlow = smoothstep(strandWidth * 5.0, 0.0, abs(dx)) * depth * 0.15;
            float innerGlow = smoothstep(strandWidth * 2.0, 0.0, abs(dx)) * depth * 0.3;
            float core = smoothstep(strandWidth, 0.0, abs(dx)) * depth * 0.5;

            lum += outerGlow + innerGlow + core;
        }
    }
    lum /= 5.0; // average the slices

    // Base pair rungs — brighter, more visible
    float y = p.y * pitch;
    float rungSpacing = M_PI_F / 4.0;
    float rungPhase = fmod(y + t * 2.5, rungSpacing);
    float nearRung = smoothstep(rungSpacing * 0.2, 0.0, abs(rungPhase));

    // Rung positions after rotation
    float hx1 = cos(y + t * 2.5) * helixRadius;
    float hz1 = sin(y + t * 2.5) * helixRadius;
    float hx2 = cos(y + t * 2.5 + M_PI_F) * helixRadius;
    float hz2 = sin(y + t * 2.5 + M_PI_F) * helixRadius;

    float rx1 = hx1 * cosR - hz1 * sinR;
    float rx2 = hx2 * cosR - hz2 * sinR;
    float rz1 = hx1 * sinR + hz1 * cosR;
    float rz2b = hx2 * sinR + hz2 * cosR;

    float rungLeft = min(rx1, rx2);
    float rungRight = max(rx1, rx2);
    float rungDepth = (rz1 + rz2b) * 0.5 * 0.8 + 0.6;
    rungDepth = clamp(rungDepth, 0.1, 1.0);

    if (p.x > rungLeft - 0.03 && p.x < rungRight + 0.03) {
        // Rung with center dot pattern (base pairs)
        float rungMid = (rungLeft + rungRight) * 0.5;
        float basePair = smoothstep(0.03, 0.0, abs(p.x - rungMid));
        lum += nearRung * 0.35 * rungDepth + basePair * nearRung * 0.2 * rungDepth;
    }

    // Phosphor glow: bright ambient around the helix
    float helixCenter = 0.0; // helix is centered on x=0
    float distFromAxis = abs(p.x - helixCenter);
    float phosphor = smoothstep(helixRadius * 2.0, 0.0, distFromAxis) * 0.12;
    phosphor *= smoothstep(1.0, 0.0, abs(p.y)); // fade at top/bottom
    lum += phosphor;

    // Floating molecules — brighter
    float2 molGrid = float2(p.x * 6.0, p.y * 10.0);
    float2 molId = floor(molGrid);
    float2 molUv = fract(molGrid);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = molId + neighbor;
            float2 rnd = hash22(id);
            float2 pos = neighbor + rnd + 0.15 * float2(sin(t * 1.2 + rnd.x * 6.28), cos(t + rnd.y * 6.28));
            float d = length(molUv - pos);
            float bright = hash21(id);
            if (bright > 0.6) {
                lum += smoothstep(0.15, 0.0, d) * bright * 0.15;
            }
        }
    }

    // Boost overall brightness
    lum *= 1.6;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
