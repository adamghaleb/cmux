#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// String Theory: vibrating 1D strings in 2D space with harmonic overtones

[[ stitchable ]]
half4 stringTheoryEffect(
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

    // 9 vibrating strings at different angles through the center
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float stringAngle = fi * M_PI_F / 9.0 + t * 0.06;

        // String axis
        float2 axis = float2(cos(stringAngle), sin(stringAngle));
        float2 perp = float2(-axis.y, axis.x);

        // Project point onto string axis
        float along = dot(p, axis);
        float across = dot(p, perp);

        // String boundaries
        float stringLen = 0.8 + 0.1 * sin(t * 0.3 + fi);
        float insideString = smoothstep(stringLen, stringLen - 0.05, abs(along));

        if (insideString < 0.001) continue;

        // Superposition of harmonic modes
        float stringDisplacement = 0.0;
        for (int h = 1; h <= 7; h++) {
            float fh = float(h);
            // Standing wave: sin(n*pi*x/L) * cos(n*omega*t)
            float amplitude = 0.03 / fh; // higher harmonics have less amplitude
            float spatial = sin(fh * M_PI_F * (along + stringLen) / (2.0 * stringLen));
            float temporal = cos(fh * t * (0.8 + fi * 0.05) + fi * fh * 0.3);

            // Mode excitation varies over time
            float excitation = sin(t * 0.15 + fh * 0.7 + fi * 0.5) * 0.5 + 0.5;
            stringDisplacement += amplitude * spatial * temporal * excitation;
        }

        // String line: distance from the displaced string
        float stringDist = abs(across - stringDisplacement);
        float stringGlow = smoothstep(0.008, 0.0, stringDist) * insideString;

        // String aura: softer glow
        float aura = exp(-stringDist * 80.0) * insideString * 0.15;

        // Node points: where displacement is near zero for all harmonics
        float nodeGlow = 0.0;
        for (int h = 1; h <= 3; h++) {
            float fh = float(h);
            float nodePos = sin(fh * M_PI_F * (along + stringLen) / (2.0 * stringLen));
            nodeGlow += smoothstep(0.1, 0.0, abs(nodePos)) * smoothstep(0.02, 0.0, stringDist);
        }
        nodeGlow *= insideString * 0.05;

        // Endpoint tension
        float endDist = min(abs(along - stringLen), abs(along + stringLen));
        float endpoint = smoothstep(0.03, 0.0, endDist) * smoothstep(0.02, 0.0, abs(across));
        endpoint *= 0.25;

        lum += stringGlow * 0.2 + aura + nodeGlow + endpoint;
    }

    // String interaction: where strings cross, extra energy
    float crossEnergy = 0.0;
    for (int i = 0; i < 9; i++) {
        for (int j = i + 1; j < 9; j++) {
            float ai = float(i) * M_PI_F / 9.0 + t * 0.06;
            float aj = float(j) * M_PI_F / 9.0 + t * 0.06;
            float2 axI = float2(cos(ai), sin(ai));
            float2 axJ = float2(cos(aj), sin(aj));

            // Intersection point (both strings pass through origin, so intersection is near origin)
            // But displaced strings intersect at various points
            float det = axI.x * axJ.y - axI.y * axJ.x;
            if (abs(det) < 0.01) continue;

            float2 intersection = float2(0.0); // simplified: near origin
            float d = length(p - intersection);
            crossEnergy += smoothstep(0.06, 0.0, d) * 0.01;
        }
    }
    lum += crossEnergy;

    // Compactified extra dimensions: tiny circular vibrations at regular intervals
    float compact = 0.0;
    float2 compactGrid = fract(p * 5.0) - 0.5;
    float compactR = length(compactGrid);
    float compactAngle = atan2(compactGrid.y, compactGrid.x);
    for (int m = 1; m <= 4; m++) {
        float fm = float(m);
        float modeR = 0.08 + 0.02 * sin(t * fm + fm);
        float wave = sin(compactAngle * fm - t * 2.0 * fm);
        compact += smoothstep(0.01, 0.0, abs(compactR - modeR * (1.0 + wave * 0.2))) * 0.03;
    }
    lum += compact;

    // Background: quantum foam
    float foam = simplex2d(p * 12.0 + float2(t * 0.3, 0.0));
    foam = foam * foam * 0.04;
    lum += foam;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
