#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Event Horizon: a black hole pulling everything inward — accretion disk,
// gravitational lensing, Hawking radiation, and nebula distortion

[[ stitchable ]]
half4 eventHorizonEffect(
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

    float r = length(p);
    float ang = atan2(p.y, p.x);

    float lum = 0.0;

    // --- Central void: absolute darkness at the core ---
    float voidMask = smoothstep(0.08, 0.14, r);

    // --- Event horizon bright ring ---
    float horizonRadius = 0.15 + 0.005 * sin(t * 0.8);
    float horizonRing = smoothstep(0.025, 0.0, abs(r - horizonRadius));
    float horizonFlicker = 0.7 + 0.3 * sin(ang * 12.0 + t * 3.0) *
                           (0.8 + 0.2 * sin(ang * 7.0 - t * 1.5));
    lum += horizonRing * horizonFlicker * 0.6;

    // --- Accretion disk: logarithmic spiral arms ---
    // Gravitational warping: angle advances faster near the center (frame-dragging)
    float tunnelDepth = 1.0 / (r + 0.1);
    float warpedAng = ang + tunnelDepth * 0.5 + t * 0.3;

    // Multiple spiral arms with different densities
    for (int arm = 0; arm < 4; arm++) {
        float fa = float(arm);
        float armOffset = fa * M_PI_F * 0.5;
        float armPhase = fa * 1.3;

        // Logarithmic spiral: angle = a + b * log(r)
        float spiral = warpedAng + armOffset + log(r + 0.05) * 3.5;
        float spiralLine = sin(spiral * 3.0 + t * 0.5 + armPhase);
        spiralLine = smoothstep(0.3, 0.8, spiralLine);

        // Disk envelope: thin disk that thins near the hole
        float diskEnv = smoothstep(0.12, 0.2, r) * smoothstep(1.0, 0.25, r);

        // Radial brightness falloff (brighter closer to hole)
        float radialBright = 1.0 / (1.0 + r * 3.0);

        // Noise turbulence in the disk
        float turbulence = simplex2d(float2(warpedAng * 3.0, tunnelDepth * 0.5) + t * 0.2);
        turbulence = turbulence * 0.3 + 0.7;

        lum += spiralLine * diskEnv * radialBright * turbulence * 0.2;
    }

    // --- Photon sphere: secondary image ring from gravitational lensing ---
    float photonRadius = 0.22 + 0.008 * sin(t * 0.6);
    float photonRing = smoothstep(0.015, 0.0, abs(r - photonRadius));

    // Lensed image: use fract on tunnel depth for repeated structure
    float lensedPattern = fract(tunnelDepth * 0.3 + t * 0.1);
    lensedPattern = sin(lensedPattern * 6.28 * 3.0) * 0.5 + 0.5;
    float lensedAng = sin(ang * 8.0 + tunnelDepth * 2.0 - t * 1.0);
    lensedAng = smoothstep(0.2, 0.6, lensedAng);

    lum += photonRing * (0.5 + lensedPattern * 0.3 + lensedAng * 0.2) * 0.4;

    // --- Einstein ring: bright thin ring at a specific radius ---
    float einsteinR = 0.35 + 0.01 * sin(t * 0.4);
    float einsteinRing = smoothstep(0.01, 0.0, abs(r - einsteinR));
    float einsteinMod = sin(ang * 16.0 - t * 0.8) * 0.3 + 0.7;
    lum += einsteinRing * einsteinMod * 0.25;

    // --- Hawking radiation: tiny noise particles escaping outward ---
    float2 hawkingP = p * 20.0;
    float2 hawkingCellId = floor(hawkingP);
    float2 hawkingCellUv = fract(hawkingP) - 0.5;
    float2 hawkingRnd = hash22(hawkingCellId);

    // Particles drift outward (radial motion)
    float particlePhase = hawkingRnd.x * 6.28;
    float particleLife = fract(t * 0.15 + hawkingRnd.y);
    float2 particlePos = (hawkingRnd - 0.5) * 0.6;
    particlePos += normalize(hawkingCellId + 0.5) * particleLife * 0.1; // outward drift

    float particleDist = length(hawkingCellUv - particlePos);
    float particle = smoothstep(0.05, 0.0, particleDist);
    particle *= smoothstep(0.0, 0.1, particleLife) * smoothstep(1.0, 0.7, particleLife);

    // Only show near the event horizon
    float hawkingMask = smoothstep(0.1, 0.2, r) * smoothstep(0.5, 0.25, r);
    lum += particle * hawkingMask * 0.15;

    // --- Background nebula being pulled into distortion ---
    // Warp the FBM coordinates toward the center (gravitational pull)
    float2 nebulaP = p;
    float pullStrength = 0.3 / (r + 0.2);
    nebulaP += normalize(p + 0.001) * pullStrength * 0.1;

    float nebula = fbm(nebulaP * 2.5, t * 0.15);
    nebula = nebula * 0.5 + 0.5;
    nebula *= smoothstep(0.25, 0.6, r); // Fade near hole

    // Streaking: stretch the nebula tangentially near the hole
    float tangentialStretch = simplex2d(float2(ang * 3.0, r * 5.0) + t * 0.2);
    tangentialStretch = abs(tangentialStretch);
    float stretchMask = smoothstep(0.6, 0.2, r) * smoothstep(0.15, 0.25, r);
    nebula += tangentialStretch * stretchMask * 0.2;

    lum += nebula * 0.12;

    // --- Infalling matter streams ---
    for (int stream = 0; stream < 3; stream++) {
        float fs = float(stream);
        float streamAng = fs * 2.094 + t * 0.1;
        float streamDir = ang - streamAng;
        float streamAlign = smoothstep(0.15, 0.0, abs(sin(streamDir)));
        float streamRadial = smoothstep(0.8, 0.15, r) * smoothstep(0.12, 0.2, r);
        float streamPulse = sin(r * 30.0 - t * 3.0 + fs * 2.0) * 0.3 + 0.7;
        lum += streamAlign * streamRadial * streamPulse * 0.08;
    }

    // Apply void mask (darkness at center)
    lum *= voidMask;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
