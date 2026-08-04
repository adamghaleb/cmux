#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Crystal Cavern: reflective crystal formations using repeated voronoi with sharp edges

[[ stitchable ]]
half4 crystalCavernEffect(
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

    float lum = 0.0;

    // Multi-layer crystal voronoi with sharp facets
    for (int layer = 0; layer < 4; layer++) {
        float fl = float(layer);
        float scale = 3.0 + fl * 2.5;

        // Each layer has its own domain warp for organic crystal growth
        float2 warp = float2(
            simplex2d(p * (1.0 + fl * 0.5) + float2(t * 0.15 + fl * 3.0, fl * 7.0)),
            simplex2d(p * (1.0 + fl * 0.5) + float2(fl * 5.0, t * 0.12 + fl * 2.0))
        );
        float2 lp = p * scale + warp * 0.3;

        float2 cellId = floor(lp);
        float2 cellUv = fract(lp);

        float minDist = 10.0;
        float secondDist = 10.0;
        float thirdDist = 10.0;
        float closestHash = 0.0;

        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float2 neighbor = float2(float(dx), float(dy));
                float2 id = cellId + neighbor;
                float2 rnd = hash22(id);

                // Crystal seeds barely move - just subtle breathing
                float2 point = neighbor + rnd + 0.03 * sin(t * 0.3 + rnd * 6.28);
                float d = length(cellUv - point);

                if (d < minDist) {
                    thirdDist = secondDist;
                    secondDist = minDist;
                    minDist = d;
                    closestHash = hash21(id);
                } else if (d < secondDist) {
                    thirdDist = secondDist;
                    secondDist = d;
                } else if (d < thirdDist) {
                    thirdDist = d;
                }
            }
        }

        // Sharp crystal edges (F2 - F1 creates ridge lines)
        float edge = smoothstep(0.08, 0.0, secondDist - minDist);

        // Crystal facet fill: use F3-F2 for sub-facets
        float subFacet = smoothstep(0.15, 0.0, thirdDist - secondDist);

        // Specular highlight: simulate light reflecting off facet
        float facetAngle = atan2(secondDist - minDist, thirdDist - minDist);
        float specular = pow(max(0.0, cos(facetAngle * 4.0 + t * 0.5 + fl)), 8.0);

        // Crystal inner glow: each crystal has internal light
        float innerGlow = closestHash * smoothstep(0.4, 0.0, minDist);
        innerGlow *= 0.5 + 0.5 * sin(t * 0.8 + closestHash * 6.28);

        float weight = 1.0 / (1.0 + fl * 0.8);
        lum += (edge * 0.3 + subFacet * 0.1 + specular * 0.2 + innerGlow * 0.15) * weight;
    }

    // Caustic light patterns on cavern walls (simulated with overlapping sine waves)
    float caustic = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 cp = p * (3.0 + fi) + float2(t * 0.2 * (fi + 1.0), fi * 2.0);
        caustic += sin(cp.x + sin(cp.y + t * 0.3)) * sin(cp.y + sin(cp.x - t * 0.25));
    }
    caustic = abs(caustic) / 4.0;
    caustic = smoothstep(0.0, 0.6, caustic) * 0.12;

    // Ambient occlusion: darken crevices using FBM
    float ao = fbm(p * 4.0, t * 0.1) * 0.5 + 0.5;
    ao = smoothstep(0.2, 0.8, ao);

    lum = lum * ao + caustic;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
