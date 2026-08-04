#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Topographic Flow: contour lines that flow like living liquid terrain

[[ stitchable ]]
half4 topographicFlowEffect(
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

    // Generate flowing terrain height using layered FBM
    float2 warp = float2(
        simplex2d(p * 1.5 + float2(t * 0.2, 0.0)),
        simplex2d(p * 1.5 + float2(0.0, t * 0.18))
    );
    float2 wp = p + warp * 0.3;

    float height = fbm(wp * 2.0, t * 0.3);

    // Contour lines: isolines at regular height intervals
    float levels = 15.0;
    float contour = fract(height * levels);
    float line = smoothstep(0.04, 0.0, contour) + smoothstep(0.96, 1.0, contour);

    // Thicker lines every 5 levels (major contours)
    float majorContour = fract(height * levels / 5.0);
    float majorLine = smoothstep(0.08, 0.0, majorContour) + smoothstep(0.92, 1.0, majorContour);

    // Height-based fill: darker in valleys, lighter on peaks
    float fill = height * 0.5 + 0.5;
    fill = smoothstep(0.2, 0.8, fill);

    // Gradient arrows showing flow direction (simplified as directional pattern)
    float2 grad = float2(
        simplex2d(wp * 2.0 + float2(0.01, 0.0)) - simplex2d(wp * 2.0 - float2(0.01, 0.0)),
        simplex2d(wp * 2.0 + float2(0.0, 0.01)) - simplex2d(wp * 2.0 - float2(0.0, 0.01))
    );
    float gradAngle = atan2(grad.y, grad.x);
    float flowLines = sin(p.x * cos(gradAngle) * 20.0 + p.y * sin(gradAngle) * 20.0 - t * 3.0) * 0.5 + 0.5;
    flowLines *= length(grad) * 15.0;
    flowLines = clamp(flowLines, 0.0, 0.3);

    float lum = line * 0.5 + majorLine * 0.3 + fill * 0.15 + flowLines;
    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
