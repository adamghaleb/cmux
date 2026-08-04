#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Kaleidoscope: mirror-symmetry mandala with layered angular patterns

[[ stitchable ]]
half4 kaleidoscopeEffect(
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

    float angle = atan2(s.centered.y, s.centered.x);
    float t = time * 0.3;

    // 8-fold mirror symmetry
    float a8 = abs(fmod(angle + M_PI_F, M_PI_F / 4.0) - M_PI_F / 8.0);

    // Layer 1: radial petals
    float petals = sin(a8 * 16.0 + s.dist * 6.0 - t * 2.0) * 0.5 + 0.5;

    // Layer 2: spinning inner flower
    float flower = sin(a8 * 24.0 - s.dist * 10.0 + t * 3.0) * 0.5 + 0.5;

    // Layer 3: fbm organic warp inside the kaleidoscope
    float2 kalUv = float2(a8 * 3.0, s.dist);
    float organic = fbm(kalUv * 2.0, t * 0.8);
    organic = organic * 0.5 + 0.5;

    // Radial rings
    float rings = sin(s.dist * 12.0 - t * 2.5) * 0.5 + 0.5;

    float lum = petals * 0.3 + flower * 0.2 + organic * 0.3 + rings * 0.2;
    lum *= smoothstep(1.8, 0.1, s.dist);

    // Bright center core
    lum += smoothstep(0.3, 0.0, s.dist) * 0.2;
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
