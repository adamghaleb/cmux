#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Dream Catcher: concentric web rings with radial threads, caught dream particles,
// spider-silk shine, central void, and breathing organic web structure

[[ stitchable ]]
half4 dreamCatcherEffect(
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

    // Slow rotation of the entire structure
    float globalRot = t * 0.06;
    float ca = cos(globalRot), sa = sin(globalRot);
    float2 rp = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    float r = length(rp);
    float ang = atan2(rp.y, rp.x);

    float lum = 0.0;

    // --- Ring radii and thread counts ---
    float ringRadii[6] = {0.15, 0.28, 0.42, 0.58, 0.75, 0.92};
    float threadCounts[6] = {8.0, 12.0, 16.0, 20.0, 24.0, 32.0};

    // FBM warp for organic imperfection
    float organicWarp = simplex2d(rp * 3.0 + t * 0.1) * 0.03;
    float angWarp = simplex2d(float2(ang, r * 3.0) + t * 0.08) * 0.08;
    float warpedR = r + organicWarp;
    float warpedAng = ang + angWarp;

    // --- Concentric rings with breathing oscillation ---
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float baseRadius = ringRadii[i];

        // Breathing: rings oscillate in/out slightly, each at different phase
        float breathe = sin(t * 0.4 + fi * 0.9) * 0.012 * (1.0 + fi * 0.3);
        float ringR = baseRadius + breathe;

        // Ring line: thin bright line
        float ringDist = abs(warpedR - ringR);
        float ringLine = smoothstep(0.008, 0.001, ringDist);

        // Spider-silk shine: extra bright at certain angles
        float shine = sin(warpedAng * 6.0 + t * 0.3 + fi * 1.2) * 0.5 + 0.5;
        shine = pow(shine, 4.0); // Sharp highlights
        ringLine *= (0.6 + shine * 0.4);

        // Pulse along the ring (not uniform)
        float ringPulse = sin(warpedAng * 3.0 + t * 0.5 - fi * 0.7) * 0.15 + 0.85;

        lum += ringLine * ringPulse * 0.3;
    }

    // --- Radial threads between rings ---
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float innerR = (i == 0) ? 0.05 : ringRadii[i - 1];
        float outerR = ringRadii[i];
        float N = threadCounts[i];

        // Only draw threads in the annular region between rings
        float annularMask = smoothstep(innerR - 0.01, innerR + 0.01, warpedR) *
                            smoothstep(outerR + 0.01, outerR - 0.01, warpedR);

        // Radial thread lines
        float threadAng = fmod(warpedAng + M_PI_F + fi * 0.05, 2.0 * M_PI_F / N);
        float threadDist = abs(threadAng - M_PI_F / N);
        // Convert angular distance to spatial distance at this radius
        float spatialDist = threadDist * warpedR;
        float threadLine = smoothstep(0.008, 0.001, spatialDist);

        // Spider-silk shimmer on threads
        float threadShine = sin(warpedR * 40.0 + t * 0.8 + fi * 2.0) * 0.5 + 0.5;
        threadShine = pow(threadShine, 3.0);
        threadLine *= (0.5 + threadShine * 0.5);

        lum += threadLine * annularMask * 0.22;

        // --- Intersection nodes: where threads meet rings ---
        // Bright dots at intersection points
        float ringR = ringRadii[i];
        float nodeRadialDist = abs(warpedR - ringR);
        float nodeMask = smoothstep(0.02, 0.0, nodeRadialDist);

        float nodeAngDist = spatialDist;
        float nodeAngMask = smoothstep(0.015, 0.0, nodeAngDist);

        float node = nodeMask * nodeAngMask;
        float nodePulse = sin(t * 0.6 + fi * 1.3 + floor(warpedAng * N / (2.0 * M_PI_F)) * 0.8) * 0.25 + 0.75;
        lum += node * nodePulse * 0.4;
    }

    // --- Central void / eye ---
    float voidEdge = smoothstep(0.04, 0.08, r);
    float eyeRing = smoothstep(0.01, 0.0, abs(r - 0.06));
    float eyePulse = sin(t * 0.3) * 0.15 + 0.85;
    lum += eyeRing * eyePulse * 0.4;

    // Subtle inner glow
    float innerGlow = smoothstep(0.12, 0.03, r) * 0.15;
    float innerPulse = sin(t * 0.5 + ang * 4.0) * 0.3 + 0.7;
    lum += innerGlow * innerPulse;

    // --- Caught "dreams": Voronoi particles trapped in web cells ---
    float dreamScale = 8.0;
    float2 dreamP = rp * dreamScale;
    float2 dreamCellId = floor(dreamP);
    float2 dreamCellUv = fract(dreamP) - 0.5;

    float minDreamDist = 10.0;
    float2 closestDreamId = float2(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = dreamCellId + neighbor;
            float2 rnd = hash22(id);

            float2 dpos = neighbor + (rnd - 0.5) * 0.6;
            // Dreams drift gently
            dpos += 0.08 * float2(
                sin(t * 0.3 + rnd.x * 6.28),
                cos(t * 0.25 + rnd.y * 6.28)
            );

            float dd = length(dreamCellUv - dpos);
            if (dd < minDreamDist) {
                minDreamDist = dd;
                closestDreamId = id;
            }
        }
    }

    // Dream particle body
    float dreamHash = hash21(closestDreamId);
    float dreamBody = smoothstep(0.12, 0.04, minDreamDist);

    // Internal shimmer
    float shimmerAng = atan2(dreamCellUv.y, dreamCellUv.x);
    float shimmer = sin(shimmerAng * 5.0 + t * 1.5 + dreamHash * 6.28) * 0.5 + 0.5;
    shimmer *= smoothstep(0.12, 0.0, minDreamDist);

    // Only show dreams between rings (not on top of them)
    float dreamMask = smoothstep(0.1, 0.2, r) * smoothstep(0.95, 0.8, r);
    // Per-dream visibility (not all cells have dreams)
    float dreamVisible = step(0.45, dreamHash); // ~55% of cells have dreams

    lum += (dreamBody * 0.2 + shimmer * 0.12) * dreamMask * dreamVisible;

    // Dream aura
    float dreamAura = smoothstep(0.2, 0.08, minDreamDist) * 0.06;
    lum += dreamAura * dreamMask * dreamVisible;

    // --- Outer frame ring ---
    float frameR = 0.95 + 0.008 * sin(t * 0.35);
    float frame = smoothstep(0.015, 0.003, abs(r - frameR));
    float framePulse = sin(ang * 8.0 + t * 0.4) * 0.2 + 0.8;
    lum += frame * framePulse * 0.3;

    // Decorative feather-like dangles at bottom (3 hanging threads)
    for (int f = 0; f < 3; f++) {
        float ff = float(f);
        float featherAng = -M_PI_F * 0.5 + (ff - 1.0) * 0.35; // Bottom, spread out
        float2 featherDir = float2(cos(featherAng), sin(featherAng));
        float2 featherP = rp - featherDir * frameR;

        // Project onto feather direction
        float along = dot(featherP, -featherDir);
        float across = abs(dot(featherP, float2(-featherDir.y, featherDir.x)));

        float featherMask = smoothstep(-0.01, 0.02, along) * smoothstep(0.35, 0.0, along);
        float featherLine = smoothstep(0.01, 0.002, across) * featherMask;

        // Sway
        float sway = sin(t * 0.3 + ff * 1.5) * 0.02;
        featherLine *= smoothstep(0.02, 0.005, abs(across - sway));

        // Beads on feathers
        float bead = smoothstep(0.02, 0.0, length(featherP + featherDir * 0.15));
        bead += smoothstep(0.015, 0.0, length(featherP + featherDir * 0.28));

        lum += (featherLine * 0.15 + bead * 0.2) * 0.6;
    }

    // --- FBM organic overlay ---
    float organic = fbm(rp * 2.5, t * 0.15);
    organic = organic * 0.5 + 0.5;
    lum += organic * 0.04;

    // Apply void at center
    lum *= voidEdge;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
