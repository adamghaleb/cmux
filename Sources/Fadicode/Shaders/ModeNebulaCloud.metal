#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Nebula Cloud: deep space gas cloud with volumetric depth

[[ stitchable ]]
half4 nebulaCloudEffect(
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

    // Multiple FBM layers at different scales simulating depth
    float cloud = 0.0;

    // Background layer: large smooth structures
    float bg = fbm(p * 1.0 + float2(t * 0.05, t * 0.03), t * 0.2);
    bg = bg * 0.5 + 0.5;
    cloud += bg * 0.3;

    // Mid layer: medium detail, domain-warped
    float2 midWarp = float2(
        fbm(p * 1.5 + float2(3.7, 1.2), t * 0.25),
        fbm(p * 1.5 + float2(8.3, 2.8), t * 0.22)
    );
    float mid = fbm(p * 2.0 + midWarp * 0.5, t * 0.3);
    mid = mid * 0.5 + 0.5;
    mid = smoothstep(0.2, 0.8, mid);
    cloud += mid * 0.35;

    // Foreground layer: fine detail, faster
    float2 fgWarp = float2(
        simplex2d(p * 3.0 + float2(t * 0.15, 0.0)),
        simplex2d(p * 3.0 + float2(0.0, t * 0.12))
    );
    float fg = fbm(p * 4.0 + fgWarp * 0.3, t * 0.4);
    fg = fg * 0.5 + 0.5;
    fg = smoothstep(0.3, 0.9, fg);
    cloud += fg * 0.25;

    // Stars peeking through: bright points in dark areas
    float aspect = viewWidth / viewHeight;
    float2 starGrid = float2(s.uv.x * aspect, s.uv.y) * 30.0;
    float2 starId = floor(starGrid);
    float2 starUv = fract(starGrid);
    float stars = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = starId + neighbor;
            float2 rnd = hash22(id);
            float bright = hash21(id + 0.5);
            if (bright > 0.85) { // Only bright stars show
                float d = length(starUv - neighbor - rnd);
                float twinkle = sin(t * (1.0 + bright * 3.0) + bright * 6.28) * 0.3 + 0.7;
                stars += smoothstep(0.08, 0.0, d) * twinkle * (1.0 - cloud * 1.5);
            }
        }
    }

    // Emission glow: bright areas within cloud
    float emission = smoothstep(0.5, 0.9, cloud) * 0.3;

    float lum = cloud + stars * 0.3 + emission;
    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
