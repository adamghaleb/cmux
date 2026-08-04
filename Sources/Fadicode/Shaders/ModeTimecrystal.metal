#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Timecrystal: a structure that repeats in TIME rather than space.
// Iterative folding where each iteration applies a different time offset,
// creating temporal crystallization. 8 fold iterations with time-shifted phases,
// crystalline facet edges, breathing modulation, cross-hatch interference.

[[ stitchable ]]
half4 timecrystalEffect(
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

    // --- Primary fold system: temporal crystallization ---
    float2 z = p * 2.8;
    float foldAccum = 0.0;
    float edgeAccum = 0.0;

    for (int i = 0; i < 8; i++) {
        float fi = float(i);

        // Each iteration has a DIFFERENT time offset: the temporal crystal lattice
        float timeOffset = fi * 0.618033; // Golden ratio spacing in time
        float localT = t + timeOffset;

        // Fold: absolute value creates mirror symmetry
        z = abs(z) - 0.85 + 0.12 * sin(localT * 0.4 + fi * 0.9);

        // Time-dependent rotation: each fold rotates at a different temporal phase
        float angle = localT * 0.15 + fi * 0.35 + sin(localT * 0.2 + fi) * 0.3;
        float ca = cos(angle);
        float sa = sin(angle);
        z = float2(z.x * ca - z.y * sa, z.x * sa + z.y * ca);

        // Scale: slight growth per iteration
        z *= 1.15 + 0.05 * sin(localT * 0.3);

        // Crystalline facet edges: abs() creates diamond-like cuts
        float facetX = abs(z.x);
        float facetY = abs(z.y);
        float facet = min(facetX, facetY);
        float facetEdge = smoothstep(0.08, 0.0, facet);
        edgeAccum += facetEdge / (1.0 + fi * 0.35);

        // Fold distance accumulation: structure from the fold geometry
        float foldDist = min(abs(z.x), abs(z.y));
        float foldLine = smoothstep(0.12, 0.0, foldDist);
        foldAccum += foldLine / (1.0 + fi * 0.3);

        // Cross-axis interference: difference between fold axes
        float crossTerm = abs(abs(z.x) - abs(z.y));
        float cross = smoothstep(0.15, 0.0, crossTerm);
        foldAccum += cross * 0.08 / (1.0 + fi * 0.5);
    }

    // --- Cross-hatch interference layer ---
    // Two fold systems at different orientations create interference
    float2 z2 = p * 2.5;
    float crossHatch = 0.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float localT = t + fi * 0.382; // Different golden offset

        z2 = abs(z2) - 0.7 + 0.08 * sin(localT * 0.5);

        // Rotate at perpendicular angle to primary system
        float angle = -localT * 0.12 + fi * 0.5 + M_PI_F * 0.25;
        float ca = cos(angle);
        float sa = sin(angle);
        z2 = float2(z2.x * ca - z2.y * sa, z2.x * sa + z2.y * ca);

        z2 *= 1.1;

        float hatch = smoothstep(0.1, 0.0, min(abs(z2.x), abs(z2.y)));
        crossHatch += hatch / (1.0 + fi * 0.4);
    }

    // --- Temporal shimmer: the crystal's time-periodic glow ---
    // Multiple frequencies beating against each other
    float shimmer = sin(t * 0.7) * sin(t * 0.7 * 1.618) * sin(t * 0.7 * 2.618);
    shimmer = shimmer * 0.15 + 0.85;

    // --- Glow at fold intersections (crystalline nodes) ---
    float nodeGlow = smoothstep(0.3, 0.0, length(fract(z * 0.3) - 0.5));

    // --- Breathing modulation ---
    float breathe = sin(t * 0.4) * 0.12 + sin(t * 0.27) * 0.08;

    // --- Soft center glow (crystal core) ---
    float core = smoothstep(0.5, 0.0, s.dist) * 0.15;

    // --- FBM organic texture overlay ---
    float organic = fbm(p * 3.0, t * 0.3);
    float organicMod = 0.88 + organic * 0.15;

    // --- Combine all layers ---
    lum = foldAccum * 0.35
        + edgeAccum * 0.2
        + crossHatch * 0.15
        + nodeGlow * 0.15
        + core;

    lum *= shimmer;
    lum *= (1.0 + breathe);
    lum *= organicMod;

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
