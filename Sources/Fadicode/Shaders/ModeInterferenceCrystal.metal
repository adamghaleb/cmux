#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Interference Crystal: multiple wave sources creating crystal-like interference

[[ stitchable ]]
half4 interferenceCrystalEffect(
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

    // 7 wave sources arranged in sacred geometry pattern
    float wave = 0.0;

    // Central source
    float d0 = length(p);
    wave += sin(d0 * 20.0 - t * 3.0);

    // 6 sources in hexagonal arrangement
    for (int i = 0; i < 6; i++) {
        float angle = float(i) * M_PI_F / 3.0 + t * 0.08;
        float radius = 0.6 + 0.1 * sin(t * 0.3 + float(i));
        float2 source = float2(cos(angle), sin(angle)) * radius;
        float d = length(p - source);
        float freq = 18.0 + 2.0 * sin(t * 0.2 + float(i) * 1.047);
        wave += sin(d * freq - t * 2.5 + float(i) * 0.5);
    }

    // Normalize and create interference pattern
    wave /= 7.0;

    // Sharp crystal facets from the interference
    float crystal = abs(wave);
    crystal = smoothstep(0.0, 0.5, crystal);

    // Node lines: where wave cancels perfectly
    float nodes = smoothstep(0.08, 0.0, abs(wave));

    // Secondary pattern: multiply two rotated versions for moire-like crystal
    float2 rp = float2(
        p.x * cos(t * 0.1) - p.y * sin(t * 0.1),
        p.x * sin(t * 0.1) + p.y * cos(t * 0.1)
    );
    float wave2 = 0.0;
    for (int i = 0; i < 4; i++) {
        float angle = float(i) * M_PI_F * 0.5;
        float2 source = float2(cos(angle), sin(angle)) * 0.8;
        wave2 += sin(length(rp - source) * 15.0 - t * 2.0);
    }
    wave2 /= 4.0;
    float cross = abs(wave * wave2);
    cross = smoothstep(0.0, 0.3, cross);

    float lum = crystal * 0.4 + nodes * 0.4 + cross * 0.3;
    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
