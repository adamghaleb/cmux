#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Chrysanthemum: infinite fractal petals radiating outward, DMT-inspired

[[ stitchable ]]
half4 chrysanthemumEffect(
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
    float angle = atan2(p.y, p.x);
    float r = s.dist;

    // Multiple petal layers with increasing complexity
    float petals = 0.0;

    // Layer 1: 8 primary petals
    float p1 = sin(angle * 8.0 + t * 0.5) * 0.5 + 0.5;
    p1 *= smoothstep(1.2, 0.1, r);
    p1 *= (sin(r * 15.0 - t * 3.0) * 0.5 + 0.5);
    petals += p1 * 0.4;

    // Layer 2: 13 secondary petals (fibonacci-like), counter-rotating
    float p2 = sin(angle * 13.0 - t * 0.7 + r * 3.0) * 0.5 + 0.5;
    p2 *= smoothstep(1.4, 0.05, r);
    p2 *= (sin(r * 20.0 - t * 2.0 + M_PI_F * 0.5) * 0.5 + 0.5);
    petals += p2 * 0.3;

    // Layer 3: 21 micro-petals (deep fractal detail)
    float p3 = sin(angle * 21.0 + t * 0.3 - r * 5.0) * 0.5 + 0.5;
    p3 *= smoothstep(1.0, 0.2, r);
    petals += p3 * 0.2;

    // Radial pulse rings expanding outward
    float rings = sin(r * 25.0 - t * 4.0) * 0.5 + 0.5;
    rings *= smoothstep(0.0, 0.15, r) * smoothstep(1.5, 0.3, r);
    petals += rings * 0.15;

    // Central bloom: bright core
    float core = smoothstep(0.3, 0.0, r) * 0.6;
    core *= (1.0 + 0.3 * sin(t * 2.0));

    // FBM organic warp for extra life
    float warp = fbm(p * 2.0 + float2(t * 0.2), t * 0.5) * 0.5 + 0.5;
    petals *= (0.8 + warp * 0.4);

    float lum = petals + core;
    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
