#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Resonance: coupled oscillator interference with multiple frequency harmonics beating together

[[ stitchable ]]
half4 resonanceEffect(
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
    float r = length(p);
    float angle = atan2(p.y, p.x);

    // 5 coupled oscillators at different positions with different natural frequencies
    float totalWave = 0.0;
    float totalEnvelope = 0.0;

    float2 oscPos[5];
    float oscFreq[5];
    oscPos[0] = float2(0.0, 0.0);    oscFreq[0] = 7.0;
    oscPos[1] = float2(0.3, 0.2);    oscFreq[1] = 8.0;
    oscPos[2] = float2(-0.25, 0.3);  oscFreq[2] = 9.0;
    oscPos[3] = float2(-0.3, -0.2);  oscFreq[3] = 11.0;
    oscPos[4] = float2(0.2, -0.35);  oscFreq[4] = 13.0;

    // Each oscillator drifts slightly
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        oscPos[i] += float2(
            sin(t * 0.12 + fi * 1.5) * 0.08,
            cos(t * 0.1 + fi * 2.0) * 0.08
        );
    }

    // Compute superposition of all oscillator waves
    for (int i = 0; i < 5; i++) {
        float d = length(p - oscPos[i]);
        float freq = oscFreq[i];

        // Fundamental + 3 harmonics
        for (int h = 1; h <= 4; h++) {
            float fh = float(h);
            float harmFreq = freq * fh;
            float amplitude = 1.0 / (fh * fh); // harmonics decay as 1/n^2
            float phase = t * harmFreq * 0.1 + float(i) * 0.7;
            totalWave += amplitude * sin(d * harmFreq - phase) * exp(-d * (0.5 + fh * 0.3));
        }

        // Oscillator core glow
        totalEnvelope += smoothstep(0.05, 0.0, d) * 0.15;
    }

    // Beating pattern from interference of close frequencies
    float beating = sin(p.x * 7.0 - t * 0.7) * sin(p.x * 8.0 - t * 0.8);
    beating += sin(p.y * 9.0 - t * 0.9) * sin(p.y * 11.0 - t * 1.1);
    beating *= 0.5;

    // Standing wave nodes
    float standingX = sin(p.x * 15.0) * cos(t * 1.5);
    float standingY = sin(p.y * 15.0) * cos(t * 1.3);
    float standing = abs(standingX * standingY);
    standing = smoothstep(0.0, 0.5, standing) * 0.15;

    // Chladni-like patterns: nodal lines where waves cancel
    float wave2D = totalWave / 5.0;
    float nodalLines = smoothstep(0.08, 0.0, abs(wave2D));
    float waveIntensity = abs(wave2D);
    waveIntensity = smoothstep(0.0, 0.5, waveIntensity);

    // Mode shape visualization: angular harmonics
    float modeShape = 0.0;
    for (int m = 2; m <= 6; m++) {
        float fm = float(m);
        float modeAmp = sin(t * 0.2 + fm * 0.5) * 0.5 + 0.5;
        float angularMode = cos(angle * fm + t * 0.3 * fm);
        float radialMode = sin(r * fm * 5.0 - t * 0.5);
        modeShape += angularMode * radialMode * modeAmp / (fm * fm);
    }
    modeShape = abs(modeShape);
    modeShape = smoothstep(0.0, 0.4, modeShape) * 0.15;

    // Energy concentration at resonance points
    float resonancePeaks = smoothstep(0.3, 0.6, waveIntensity) * 0.2;

    lum = nodalLines * 0.3 + waveIntensity * 0.2 + totalEnvelope + standing + modeShape + resonancePeaks + abs(beating) * 0.08;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
