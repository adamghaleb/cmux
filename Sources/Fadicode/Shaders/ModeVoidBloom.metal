#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Void Bloom: flowers blooming from nothing — expanding ring structures
// that unfurl like petals with Fibonacci subdivision, connected by FBM filaments

[[ stitchable ]]
half4 voidBloomEffect(
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

    float t = time * 0.22;
    float2 p = s.centered;

    float lum = 0.0;

    // --- 4 bloom centers with staggered life cycles ---
    float petalCounts[4] = {5.0, 8.0, 13.0, 8.0};

    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float phase = fi * 1.571; // pi/2 apart in phase

        // Bloom center position — slow drift
        float2 center = float2(
            sin(t * 0.15 + fi * 2.4) * 0.45 + cos(t * 0.1 + fi * 1.7) * 0.15,
            cos(t * 0.12 + fi * 1.9) * 0.4 + sin(t * 0.08 + fi * 3.1) * 0.1
        );

        float2 diff = p - center;
        float d = length(diff);
        float ang = atan2(diff.y, diff.x);

        // Breathing scale per bloom
        float breathe = 1.0 + 0.08 * sin(t * 0.6 + phase);

        // Life cycle: blooms emerge and fade over time
        float life = fract(t * 0.08 + fi * 0.25);
        float lifeEnvelope = smoothstep(0.0, 0.15, life) * smoothstep(1.0, 0.7, life);

        // Expanding bloom radius
        float bloomRadius = life * 0.55 * breathe;

        float N = petalCounts[i];

        // --- Petal rings (3 concentric rings per bloom) ---
        for (int ring = 0; ring < 3; ring++) {
            float fr = float(ring);
            float ringRadius = bloomRadius * (0.35 + fr * 0.3);
            float ringPhase = phase + fr * 0.8;

            // Petal shape: angular subdivision modulated by radial distance
            float petalAngle = ang + t * 0.2 * (1.0 + fi * 0.1) + ringPhase;
            float petalShape = sin(petalAngle * N + d * 8.0) * 0.5 + 0.5;

            // Sharpen the petals
            petalShape = smoothstep(0.25, 0.75, petalShape);

            // Radial envelope for this ring
            float radialEnv = smoothstep(ringRadius + 0.04, ringRadius, d) *
                              smoothstep(ringRadius - 0.08, ringRadius - 0.02, d);

            // Unfurling: outer rings appear later in life cycle
            float unfurl = smoothstep(fr * 0.12, fr * 0.12 + 0.15, life);

            lum += petalShape * radialEnv * lifeEnvelope * unfurl * 0.35;
        }

        // Central pistil glow
        float pistil = smoothstep(0.06, 0.0, d) * lifeEnvelope;
        pistil *= (sin(t * 1.2 + phase) * 0.2 + 0.8);
        lum += pistil * 0.3;

        // Stamen lines radiating from center
        float stamen = abs(sin(ang * N * 0.5 + t * 0.3 + phase));
        stamen = smoothstep(0.92, 1.0, stamen);
        float stamenMask = smoothstep(bloomRadius * 0.1, bloomRadius * 0.05, d) *
                           smoothstep(0.0, bloomRadius * 0.6, d);
        lum += stamen * stamenMask * lifeEnvelope * 0.2;
    }

    // --- FBM filament web connecting blooms ---
    float filamentNoise = fbm(p * 4.0, t * 0.25);
    float filament = smoothstep(0.0, 0.15, abs(filamentNoise));
    filament = 1.0 - filament; // Invert: bright at zero-crossings
    lum += filament * 0.1;

    // Secondary organic texture
    float organic = simplex2d(p * 6.0 + float2(t * 0.15, t * 0.12));
    organic = abs(organic);
    organic = smoothstep(0.3, 0.0, organic);
    lum += organic * 0.06;

    // Spore-like particles drifting (using hash grid)
    float2 sporeGrid = floor(p * 12.0);
    float2 sporeUv = fract(p * 12.0) - 0.5;
    float2 sporeRnd = hash22(sporeGrid);
    float2 sporePos = sporeRnd - 0.5;
    sporePos += 0.1 * float2(sin(t + sporeRnd.x * 6.28), cos(t * 0.8 + sporeRnd.y * 6.28));
    float sporeDist = length(sporeUv - sporePos);
    float spore = smoothstep(0.06, 0.0, sporeDist) * (sin(t * 0.7 + sporeRnd.x * 12.0) * 0.3 + 0.7);
    lum += spore * 0.08;

    lum *= smoothstep(1.7, 0.15, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
