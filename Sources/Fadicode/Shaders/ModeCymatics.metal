#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Cymatics: standing wave patterns like sand on vibrating plates

[[ stitchable ]]
half4 cymaticsEffect(
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

    // Multiple vibration modes superimposed
    float wave = 0.0;

    // Mode 1: circular standing wave
    float r = s.dist;
    wave += sin(r * 12.0 + t * 0.5) * cos(r * 8.0 - t * 0.3);

    // Mode 2: rectangular standing wave
    wave += sin(p.x * 10.0 + t * 0.4) * sin(p.y * 10.0 - t * 0.35) * 0.7;

    // Mode 3: hexagonal standing wave (3 axes at 60 degrees)
    float2 h1 = p;
    float2 h2 = float2(p.x * 0.5 - p.y * 0.866, p.x * 0.866 + p.y * 0.5);
    float2 h3 = float2(p.x * 0.5 + p.y * 0.866, -p.x * 0.866 + p.y * 0.5);
    wave += (sin(h1.x * 8.0 + t * 0.25) * sin(h2.x * 8.0 - t * 0.2) * sin(h3.x * 8.0 + t * 0.15)) * 0.5;

    // Nodal lines: where wave = 0, "sand" accumulates
    float nodal = 1.0 - smoothstep(0.0, 0.3, abs(wave));

    // Add bright particles at nodal intersections
    float particles = smoothstep(0.0, 0.05, abs(wave)) * smoothstep(0.15, 0.05, abs(wave));

    // Slow mode transition
    float modeBlend = sin(t * 0.15) * 0.5 + 0.5;
    float lum = mix(nodal, particles + nodal * 0.5, modeBlend);

    // Add subtle organic motion
    float organic = fbm(p * 3.0, t * 0.3) * 0.5 + 0.5;
    lum *= (0.8 + organic * 0.3);

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
