#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Jewel Lattice: crystalline tessellation of refracting jewel cells

[[ stitchable ]]
half4 jewelLatticeEffect(
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

    // Hexagonal grid for jewel placement
    float2 hp = p * 5.0;
    float2 hexGrid;
    // Hex coordinate transform
    float2 a = float2(1.0, 0.0);
    float2 b = float2(0.5, 0.866);
    float2 ha = float2(dot(hp, float2(a.x, -b.x)), dot(hp, float2(0.0, 1.0/b.y)));
    float2 hf = fract(ha);
    float2 hi = floor(ha);

    // Triangle subdivision within hex
    float tri = step(hf.x + hf.y, 1.0);
    float2 cellId = hi + (1.0 - tri);

    // Distance to cell center
    float2 cellCenter = tri > 0.5 ? hf : 1.0 - hf;
    float cellDist = length(cellCenter - float2(0.33));

    // Jewel facets: create internal reflections
    float facetAngle = atan2(cellCenter.y - 0.33, cellCenter.x - 0.33);
    float facets = sin(facetAngle * 6.0 + t + hash21(cellId) * 6.28) * 0.5 + 0.5;

    // Brilliance: bright center with faceted sparkle
    float brilliance = smoothstep(0.4, 0.0, cellDist);
    float sparkle = facets * brilliance;

    // Each jewel has a unique brightness cycle
    float phase = hash21(cellId) * 6.28;
    float pulse = sin(t * 1.5 + phase) * 0.3 + 0.7;

    // Edge glow between cells
    float edge = smoothstep(0.02, 0.06, cellDist);
    float edgeGlow = (1.0 - edge) * 0.6;

    // Deep internal refraction pattern
    float refract = sin(cellDist * 20.0 - t * 2.0 + phase) * 0.5 + 0.5;
    refract *= brilliance * 0.3;

    float lum = sparkle * 0.4 * pulse + edgeGlow + refract;

    // Overall FBM shimmer
    float shimmer = fbm(p * 3.0, t * 0.3) * 0.5 + 0.5;
    lum *= (0.7 + shimmer * 0.5);

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
