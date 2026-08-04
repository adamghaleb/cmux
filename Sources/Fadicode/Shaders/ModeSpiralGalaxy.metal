#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Spiral Galaxy: logarithmic spiral arms rotating slowly

[[ stitchable ]]
half4 spiralGalaxyEffect(
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
    float angle = atan2(s.centered.y, s.centered.x);

    // Logarithmic spiral: angle - k * log(dist)
    float k = 0.5;
    float spiral1 = sin(angle * 2.0 - log(s.dist + 0.01) * 8.0 + t * 2.0) * 0.5 + 0.5;
    float spiral2 = sin(angle * 2.0 - log(s.dist + 0.01) * 8.0 + t * 2.0 + M_PI_F) * 0.5 + 0.5;

    // Arm brightness falls off with distance
    float armFalloff = smoothstep(1.5, 0.0, s.dist);
    float arms = (spiral1 + spiral2 * 0.6) * armFalloff;

    // Core glow
    float core = smoothstep(0.4, 0.0, s.dist) * 0.5;

    // Star field: scattered points along the arms
    float aspect = viewWidth / viewHeight;
    float2 starGrid = float2(s.uv.x * aspect, s.uv.y) * 20.0;
    float2 starId = floor(starGrid);
    float2 starUv = fract(starGrid);
    float stars = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = starId + neighbor;
            float2 rnd = hash22(id);
            float2 pos = neighbor + rnd;
            float d = length(starUv - pos);
            float bright = hash21(id + 0.5);
            float twinkle = sin(t * (1.0 + bright * 2.0) + bright * 6.28) * 0.5 + 0.5;
            stars += smoothstep(0.15, 0.0, d) * bright * twinkle * 0.3;
        }
    }

    // Nebula: fbm noise in spiral coordinates
    float nebula = fbm(float2(angle * 0.5 + t * 0.1, s.dist * 2.0), t * 0.5);
    nebula = nebula * 0.5 + 0.5;

    float lum = arms * 0.5 + core + stars + nebula * 0.15;
    lum *= smoothstep(1.8, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
