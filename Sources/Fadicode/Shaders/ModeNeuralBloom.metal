#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Neural Bloom: dendritic branching patterns like neurons firing

[[ stitchable ]]
half4 neuralBloomEffect(
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

    // Multiple neuron cell bodies with firing patterns
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float phase = fi * 1.257; // golden angle-ish spacing

        // Cell body position drifts slowly
        float2 soma = float2(
            sin(t * 0.3 + phase) * 0.5,
            cos(t * 0.25 + phase * 1.3) * 0.4
        );

        float2 diff = p - soma;
        float d = length(diff);
        float ang = atan2(diff.y, diff.x);

        // Cell body glow
        float body = smoothstep(0.15, 0.0, d) * 0.5;

        // Dendrites: branching arms radiating outward
        float dendrites = 0.0;
        for (int j = 0; j < 6; j++) {
            float dAngle = float(j) * M_PI_F / 3.0 + fi;
            float angDiff = abs(fmod(ang - dAngle + M_PI_F, 2.0 * M_PI_F) - M_PI_F);
            float arm = smoothstep(0.15, 0.0, angDiff) * smoothstep(0.0, 0.05, d) * smoothstep(0.8, 0.1, d);

            // Branching detail via noise
            float branch = simplex2d(float2(ang * 3.0 + fi, d * 8.0 + t * 0.5));
            arm *= (0.7 + branch * 0.5);
            dendrites += arm;
        }

        // Action potential: firing pulse traveling along dendrites
        float firePhase = fract(t * 0.4 + fi * 0.2);
        float pulse = smoothstep(0.0, 0.05, d - firePhase * 0.8) *
                       smoothstep(firePhase * 0.8 + 0.15, firePhase * 0.8, d);
        pulse *= dendrites * 2.0;

        lum += body + dendrites * 0.2 + pulse * 0.4;
    }

    // Synaptic background: subtle noise field representing neurotransmitters
    float synaptic = fbm(p * 4.0, t * 0.3) * 0.5 + 0.5;
    lum += synaptic * 0.08;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
