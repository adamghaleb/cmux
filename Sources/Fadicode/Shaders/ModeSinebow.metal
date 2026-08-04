#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

[[ stitchable ]]
half4 sinebowEffect(
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

    float t = time * 0.35; // slowed from raw time
    float aspectRatio = viewWidth / viewHeight;
    float2 p = s.uv * 2.0 - 1.0;
    p.x *= aspectRatio;

    float wave = sin(p.x + t);
    wave *= wave * 50.0;

    float3 waveColor = float3(0.0);
    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float luma = abs(1.0 / (100.0 * p.y + wave));
        float y = sin(p.x * sin(t) + fi * 0.2 + t);
        p.y += 0.05 * y;

        float3 rainbow = float3(
            sin(fi * 0.3 + t) * 0.5 + 0.5,
            sin(fi * 0.3 + 2.0 + sin(t * 0.3) * 2.0) * 0.5 + 0.5,
            sin(fi * 0.3 + 4.0) * 0.5 + 0.5
        );
        waveColor += rainbow * luma;
    }

    float lum = dot(waveColor, float3(0.2126, 0.7152, 0.0722));
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
