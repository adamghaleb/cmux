#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Architect's Gaze: a massive singular watchful entity filling the screen.
// Central eye made from nested rotating polygons (triangle-hexagon morph),
// radiating geometric mandala rays, concentric aura rings, internal fractal,
// FBM breathing body, slow circular drift path.

[[ stitchable ]]
half4 architectsGazeEffect(
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

    // --- Eye center drifts in a slow figure-8 (lemniscate) path ---
    float2 eyeCenter = float2(
        sin(t * 0.12) * 0.08,
        sin(t * 0.12 * 2.0) * 0.04
    );

    float2 ep = p - eyeCenter; // Relative to eye
    float eDist = length(ep);
    float eAngle = atan2(ep.y, ep.x);

    // --- FBM breathing body shape ---
    // The entity's body is a noise-deformed sphere
    float bodyNoise = fbm(float2(eAngle * 1.5 / M_PI_F, t * 0.3), t * 0.3);
    float bodyRadius = 0.95 + bodyNoise * 0.15 + 0.05 * sin(t * 0.3);
    float body = smoothstep(bodyRadius, bodyRadius * 0.6, eDist);
    float bodyEdge = smoothstep(0.06, 0.0, abs(eDist - bodyRadius)) * 0.3;

    // --- The Eye: nested polygon layers ---
    float eyeR = 0.25 + 0.02 * sin(t * 0.5);
    float eye = 0.0;

    // 6 nested polygon rings, morphing triangle <-> hexagon
    for (int ring = 0; ring < 6; ring++) {
        float fr = float(ring);
        float ringR = eyeR * (0.3 + fr * 0.14);

        // Morph between triangle (3) and hexagon (6) over time
        float morphPhase = sin(t * 0.25 + fr * 0.5) * 0.5 + 0.5;
        float sides = mix(3.0, 6.0, morphPhase);

        // Each ring rotates at a different speed and direction
        float rotAngle = eAngle + t * (0.2 + fr * 0.06) * (fmod(fr, 2.0) < 1.0 ? 1.0 : -1.0);

        // Polygon distance function
        float polyShape = cos(M_PI_F / sides) / cos(fmod(rotAngle + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);
        float polyDist = eDist / ringR;

        // Ring outline
        float polyRing = smoothstep(0.06, 0.0, abs(polyDist - polyShape));
        eye += polyRing * 0.2 / (1.0 + fr * 0.15);
    }

    // --- Inner pupil: fractal geometry inside the eye ---
    float pupil = 0.0;
    if (eDist < eyeR * 0.3) {
        float2 innerP = ep / (eyeR * 0.3); // Normalize to unit circle
        // Mini fold fractal inside the pupil
        float2 fz = innerP * 3.0;
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            fz = abs(fz) - 0.6;
            float fAngle = t * 0.3 + fi * 0.7;
            float fca = cos(fAngle);
            float fsa = sin(fAngle);
            fz = float2(fz.x * fca - fz.y * fsa, fz.x * fsa + fz.y * fca);
            fz *= 1.3;
        }
        float fractalDist = min(abs(fz.x), abs(fz.y));
        pupil = smoothstep(0.15, 0.0, fractalDist) * 0.6;
        pupil *= smoothstep(eyeR * 0.3, eyeR * 0.05, eDist); // Fade at pupil edge
    }

    // --- Pupil center glow ---
    float pupilGlow = smoothstep(0.08, 0.0, eDist) * 0.5;
    pupilGlow *= (0.7 + 0.3 * sin(t * 0.6));

    // --- Radiating mandala rays ---
    float rays = 0.0;
    // Multiple ray frequencies for richness
    float ray1 = sin(eAngle * 12.0 + t * 0.3) * 0.5 + 0.5;
    float ray2 = sin(eAngle * 8.0 - t * 0.25 + 1.0) * 0.5 + 0.5;
    float ray3 = sin(eAngle * 24.0 + t * 0.15) * 0.5 + 0.5;

    // Rays radiate outward from eye, fade with distance
    float rayMask = smoothstep(eyeR * 0.8, eyeR * 2.0, eDist) * smoothstep(bodyRadius, bodyRadius * 0.5, eDist);
    rays = (ray1 * 0.4 + ray2 * 0.35 + ray3 * 0.15) * rayMask;

    // Radial distance modulation on rays: creates concentric structure
    float radialMod = sin(eDist * 20.0 - t * 1.5) * 0.3 + 0.7;
    rays *= radialMod;

    // --- Concentric aura rings ---
    float aura = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float auraR = eyeR + fi * 0.1 + 0.05 * sin(t * 0.4 + fi * 0.8);
        float auraWidth = 0.012 + fi * 0.003;
        float pulse = sin(t * (0.4 + fi * 0.1) - fi * 0.7) * 0.35 + 0.65;
        aura += smoothstep(auraWidth, 0.0, abs(eDist - auraR)) * pulse / (1.0 + fi * 0.2);
    }

    // --- Combine all layers ---
    lum = body * 0.08      // Subtle body fill
        + bodyEdge         // Body outline
        + eye              // Nested polygon rings
        + pupil            // Fractal pupil interior
        + pupilGlow        // Center glow
        + rays * 0.25      // Mandala rays
        + aura * 0.3;      // Concentric aura

    // Overall breathing
    float breathe = sin(t * 0.35) * 0.08;
    lum *= (1.0 + breathe);

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
