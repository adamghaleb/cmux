#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Fractal Rings: nested rotating concentric ring patterns at different scales

[[ stitchable ]]
half4 fractalRingsEffect(
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

    float t = time * 0.3;
    float lum = 0.0;

    // Multiple ring systems at different scales and rotation speeds
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float scale = 1.0 + fi * 0.8;
        float rotSpeed = (0.2 + fi * 0.1) * (fmod(fi, 2.0) < 1.0 ? 1.0 : -1.0);

        // Rotate coordinates for this ring layer
        float a = t * rotSpeed;
        float2 rotP = float2(
            s.centered.x * cos(a) - s.centered.y * sin(a),
            s.centered.x * sin(a) + s.centered.y * cos(a)
        );
        float d = length(rotP);

        // Concentric rings with varying thickness
        float ringFreq = 6.0 * scale;
        float ring = sin(d * ringFreq - t * 1.5) * 0.5 + 0.5;

        // Angular modulation: breaks rings into arcs
        float ringAngle = atan2(rotP.y, rotP.x);
        float arcMod = sin(ringAngle * (3.0 + fi * 2.0) + t * 0.5) * 0.5 + 0.5;

        ring *= arcMod;
        ring *= smoothstep(1.5, 0.0, d); // fade with distance

        float layerWeight = 0.35 - fi * 0.05;
        lum += ring * layerWeight;
    }

    // Bright center
    lum += smoothstep(0.25, 0.0, s.dist) * 0.2;

    lum *= smoothstep(1.8, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
