#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Quantum Field: probability clouds that collapse into Voronoi states.
// Multi-scale Voronoi cells shimmer between visible/invisible, internal
// interference patterns, glowing cell edges, FBM uncertainty overlay.

[[ stitchable ]]
half4 quantumFieldEffect(
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

    float lum = 0.0;

    // --- Primary Voronoi: quantum state cells ---
    float2 gp1 = p * 3.5;
    float2 cellId1 = floor(gp1);
    float2 cellUv1 = fract(gp1);

    float minD1 = 10.0;
    float secondD1 = 10.0;
    float closestPhase1 = 0.0;
    float2 closestCenter1 = float2(0.0);
    float2 closestId1 = float2(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId1 + neighbor;
            float2 rnd = hash22(id);

            // Cell centers drift slowly
            float2 center = neighbor + rnd + 0.25 * sin(t * 0.4 + rnd * 6.28);
            float d = length(cellUv1 - center);

            if (d < minD1) {
                secondD1 = minD1;
                minD1 = d;
                closestPhase1 = hash21(id) * 6.28;
                closestCenter1 = center;
                closestId1 = id;
            } else if (d < secondD1) {
                secondD1 = d;
            }
        }
    }

    // Cell visibility: probability collapse oscillation
    float cellHash = hash21(closestId1);
    float collapseWave = sin(t * 0.6 + closestPhase1) * sin(t * 0.23 + cellHash * 4.0);
    float visibility = smoothstep(-0.2, 0.4, collapseWave);

    // Edge glow: bright energy at cell boundaries
    float edge1 = smoothstep(0.12, 0.0, secondD1 - minD1);

    // Internal interference when cell is visible:
    // overlapping sine waves inside each cell
    float interference = 0.0;
    for (int w = 0; w < 4; w++) {
        float fw = float(w);
        float waveAngle = fw * M_PI_F * 0.5 + closestPhase1;
        float2 waveDir = float2(cos(waveAngle), sin(waveAngle));
        float2 localP = cellUv1 - closestCenter1;
        float proj = dot(localP, waveDir);
        interference += sin(proj * 25.0 - t * 2.0 + fw * 1.5) * 0.25;
    }
    interference = abs(interference);
    interference *= smoothstep(0.5, 0.1, minD1); // Fade at cell edges
    interference *= visibility;

    // --- Secondary Voronoi: smaller scale quantum fluctuations ---
    float2 gp2 = p * 7.0 + float2(t * 0.1, -t * 0.08);
    float2 cellId2 = floor(gp2);
    float2 cellUv2 = fract(gp2);

    float minD2 = 10.0;
    float secondD2 = 10.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = cellId2 + neighbor;
            float2 rnd = hash22(id);
            float2 center = neighbor + rnd + 0.2 * sin(t * 0.5 + rnd * 6.28);
            float d = length(cellUv2 - center);
            if (d < minD2) {
                secondD2 = minD2;
                minD2 = d;
            } else if (d < secondD2) {
                secondD2 = d;
            }
        }
    }

    float edge2 = smoothstep(0.08, 0.0, secondD2 - minD2);

    // --- FBM uncertainty cloud: the probability fog ---
    float uncertainty = fbm(p * 2.0 + float2(t * 0.15, -t * 0.12), t * 0.3);
    uncertainty = uncertainty * 0.5 + 0.5;
    float cloud = smoothstep(0.3, 0.7, uncertainty) * 0.25;

    // --- Standing wave field: quantum vacuum fluctuations ---
    float standing = 0.0;
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float angle = fk * M_PI_F / 3.0 + t * 0.05;
        float2 dir = float2(cos(angle), sin(angle));
        standing += sin(dot(p, dir) * 12.0 - t * 1.5 + fk * 2.0);
    }
    standing = abs(standing / 3.0);
    standing = smoothstep(0.3, 0.0, standing) * 0.12;

    // --- Combine layers ---
    float primaryCell = visibility * smoothstep(0.5, 0.0, minD1) * 0.3;
    float edgeGlow = edge1 * 0.5 * (0.6 + 0.4 * sin(t * 0.8 + closestPhase1));

    lum = primaryCell
        + interference * 0.35
        + edgeGlow
        + edge2 * 0.12
        + cloud
        + standing;

    // Breathing modulation
    float breathe = sin(t * 0.35) * 0.1;
    lum *= (1.0 + breathe);

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
