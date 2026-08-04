#ifndef WorkingStatePipeline_h
#define WorkingStatePipeline_h

#include "ShaderUtils.h"

// ============================================================
// Shared pipeline: pixelation setup + contrast + colorize + grid
// Each shader mode file includes this and calls setup/finalize.
// ============================================================

struct PipelineSetup {
    float2 uv;
    float2 centered;
    float dist;
    float gridDarken;
};

static inline PipelineSetup pipelineSetup(
    float2 position, float viewWidth, float viewHeight,
    float pixelSize, float gridOpacity
) {
    PipelineSetup s;
    s.uv = position / float2(viewWidth, viewHeight);
    s.gridDarken = 0.0;
    // Pixelation now handled in post-process layerEffect —
    // shaders always compute at full resolution for blur quality.

    s.centered = s.uv * 2.0 - 1.0;
    s.centered.x *= viewWidth / viewHeight;
    s.dist = length(s.centered);

    return s;
}

static inline half4 pipelineFinalize(
    float lum, float intensity, float3 theme,
    float posterizeLevels, float gridDarken,
    float hueSpread = 0.10, float complementMix = 0.0,
    float contrastAmount = 1.0, float brightnessAmount = 0.0
) {
    // Parameterized contrast curve:
    // contrastAmount 0.0 → s1 (single smoothstep, gentle)
    // contrastAmount 1.0 → s2 (double smoothstep, original)
    // contrastAmount 2.0 → s3 (triple smoothstep, intense)
    // contrastAmount 3.0 → linear pass-through (no curve)
    float raw = clamp(lum, 0.0, 1.0);
    float s1 = smoothstep(0.0, 1.0, raw);
    float s2 = smoothstep(0.0, 1.0, s1);
    float s3 = smoothstep(0.0, 1.0, s2);
    if (contrastAmount <= 1.0) {
        lum = mix(s1, s2, clamp(contrastAmount, 0.0, 1.0));
    } else if (contrastAmount <= 2.0) {
        lum = mix(s2, s3, clamp(contrastAmount - 1.0, 0.0, 1.0));
    } else {
        // 2.0–3.0: blend from s3 toward raw (linear) for flat look
        lum = mix(s3, raw, clamp(contrastAmount - 2.0, 0.0, 1.0));
    }

    // Brightness lift: boosts midtones and highlights while anchoring blacks.
    // Uses a power curve so lum=0 stays 0, but everything else lifts toward white.
    if (brightnessAmount > 0.001 || brightnessAmount < -0.001) {
        // Map brightness 0–1 to a gamma curve: positive = lift (gamma < 1), negative = darken (gamma > 1)
        float gamma = 1.0 / (1.0 + brightnessAmount * 2.0);
        lum = pow(clamp(lum, 0.0, 1.0), gamma);
    }

    // Output grayscale luminance — theme coloring, posterization,
    // pixelation, and grid lines are applied in the post-process pass.
    float3 color = float3(lum);

    float alpha = intensity * lum * 1.5;
    alpha = clamp(alpha, 0.0, intensity * 0.85);

    return half4(half3(color), half(alpha));
}

#endif
