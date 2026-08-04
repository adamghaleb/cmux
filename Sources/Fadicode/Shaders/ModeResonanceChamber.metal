#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Resonance Chamber: advanced cymatics with 5 pentagon wave sources,
// pentagonal standing waves, hexagonal wave overlay creating moire
// interference, slow harmonic ratio transitions, FBM organic layer.

[[ stitchable ]]
half4 resonanceChamberEffect(
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

    // --- Harmonic ratio: slowly transitions between different modes ---
    // Cycles through harmonic ratios: 1:1, 3:2, 4:3, 5:3, 2:1
    float harmonicPhase = t * 0.08;
    float harmonicBlend = fract(harmonicPhase);
    harmonicBlend = smoothstep(0.0, 1.0, harmonicBlend); // Smooth transitions
    int harmonicIndex = int(floor(fmod(harmonicPhase, 5.0)));

    // Frequency multipliers for different harmonic ratios
    float freqA, freqB;
    if (harmonicIndex == 0)      { freqA = mix(8.0,  12.0, harmonicBlend); freqB = mix(8.0,  8.0,  harmonicBlend); }
    else if (harmonicIndex == 1) { freqA = mix(12.0, 12.0, harmonicBlend); freqB = mix(8.0,  9.0,  harmonicBlend); }
    else if (harmonicIndex == 2) { freqA = mix(12.0, 15.0, harmonicBlend); freqB = mix(9.0,  9.0,  harmonicBlend); }
    else if (harmonicIndex == 3) { freqA = mix(15.0, 12.0, harmonicBlend); freqB = mix(9.0,  6.0,  harmonicBlend); }
    else                         { freqA = mix(12.0, 8.0,  harmonicBlend); freqB = mix(6.0,  8.0,  harmonicBlend); }

    // --- Pentagon wave sources: 5 sources at pentagon vertices ---
    float pentWave = 0.0;
    float pentRadius = 0.55 + 0.04 * sin(t * 0.3);

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float angle = fi * M_PI_F * 2.0 / 5.0 + t * 0.06;
        float2 source = float2(cos(angle), sin(angle)) * pentRadius;
        float d = length(p - source);

        // Primary wave from this source
        float phase = fi * 1.2566; // 2*PI/5
        pentWave += sin(d * freqA - t * 1.8 + phase);

        // Secondary harmonic from same source
        pentWave += sin(d * freqB - t * 1.2 + phase + 0.5) * 0.6;
    }
    pentWave /= 8.0; // Normalize (5 sources * ~1.6 amplitude each)

    // Nodal lines: where pentagon waves cancel = bright cymatic structures
    float pentNodal = smoothstep(0.15, 0.0, abs(pentWave));

    // Anti-nodal peaks: where waves constructively interfere
    float pentPeaks = smoothstep(0.6, 0.8, abs(pentWave));

    // --- Hexagonal wave overlay: 6 directional plane waves ---
    float hexWave = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float angle = fi * M_PI_F / 3.0 + t * 0.04;
        float2 dir = float2(cos(angle), sin(angle));
        float proj = dot(p, dir);

        // Plane wave along this direction
        hexWave += sin(proj * freqA * 1.3 - t * 1.0 + fi * 0.5);
    }
    hexWave /= 6.0;

    // Hexagonal nodal pattern
    float hexNodal = smoothstep(0.12, 0.0, abs(hexWave));

    // --- Moire interference: pentagon * hexagon interaction ---
    // The product of the two wave fields creates emergent moire patterns
    float moire = pentWave * hexWave;
    float moirePattern = smoothstep(0.0, 0.15, abs(moire));
    float moireNodes = smoothstep(0.03, 0.0, abs(moire)); // Sharp nodes at interference zeros

    // --- Central standing wave: radial component ---
    float radialWave = sin(s.dist * freqA * 1.5 - t * 0.5) * cos(s.dist * freqB - t * 0.35);
    float radialNodal = smoothstep(0.2, 0.0, abs(radialWave));

    // --- Source point glow: the 5 pentagon sources glow ---
    float sourceGlow = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float angle = fi * M_PI_F * 2.0 / 5.0 + t * 0.06;
        float2 source = float2(cos(angle), sin(angle)) * pentRadius;
        float d = length(p - source);
        float pulse = sin(t * 0.5 + fi * 1.2566) * 0.3 + 0.7;
        sourceGlow += smoothstep(0.06, 0.0, d) * pulse;
    }

    // --- FBM organic overlay: breaks up perfect symmetry ---
    float organic = fbm(p * 2.5, t * 0.3);
    float organicMod = 0.82 + organic * 0.22;

    // --- Combine all layers ---
    lum = pentNodal * 0.3
        + pentPeaks * 0.1
        + hexNodal * 0.15
        + moireNodes * 0.2
        + moirePattern * 0.08
        + radialNodal * 0.1
        + sourceGlow * 0.15;

    lum *= organicMod;

    // Slow beat modulation: the overall intensity pulses with harmonic beating
    float beat = sin(t * 0.6) * sin(t * 0.6 * 1.5) * 0.1 + 0.9;
    lum *= beat;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
