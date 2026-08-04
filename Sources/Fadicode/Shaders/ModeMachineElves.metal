#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Machine Elves: self-transforming geometric entities from DMT space

[[ stitchable ]]
half4 machineElvesEffect(
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
    float2 p = s.centered;

    // Create multiple "elf" entities as voronoi-like cells that self-transform
    float lum = 0.0;

    // Domain-warped coordinate space (entities shift and morph)
    float2 warp1 = float2(
        simplex2d(p * 1.5 + float2(t * 0.4, 0.0)),
        simplex2d(p * 1.5 + float2(0.0, t * 0.35))
    );
    float2 wp = p + warp1 * 0.4;

    // Tessellated entity grid
    float2 gp = wp * 4.0;
    float2 cellId = floor(gp);
    float2 cellUv = fract(gp) - 0.5;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId + neighbor;
            float2 rnd = hash22(id);

            // Each elf has its own phase and rotation
            float phase = hash21(id) * 6.28;
            float rot = t * (0.3 + rnd.x * 0.4) + phase;

            float2 center = neighbor + rnd * 0.6 + 0.15 * float2(sin(t + phase), cos(t * 0.8 + phase));
            float2 diff = cellUv - center;

            // Rotate the local coordinate
            float2 rd = float2(
                diff.x * cos(rot) - diff.y * sin(rot),
                diff.x * sin(rot) + diff.y * cos(rot)
            );

            // Entity shape: morphing between triangle, diamond, star
            float morphPhase = sin(t * 0.5 + phase) * 0.5 + 0.5;
            float sides = mix(3.0, 6.0, morphPhase);
            float entityAngle = atan2(rd.y, rd.x);
            float entityDist = length(rd);
            float shape = cos(M_PI_F / sides) / cos(fmod(entityAngle + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);
            float entity = smoothstep(0.02, 0.0, entityDist - shape * 0.15);

            // Internal glow pattern
            float inner = sin(entityAngle * sides + t * 2.0 + phase) * 0.5 + 0.5;
            inner *= smoothstep(shape * 0.15, 0.0, entityDist);

            lum += entity * 0.3 + inner * 0.15;
        }
    }

    // Connecting web between entities
    float web = fbm(wp * 3.0, t * 0.3);
    web = smoothstep(0.0, 0.3, abs(web));
    lum += (1.0 - web) * 0.15;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
