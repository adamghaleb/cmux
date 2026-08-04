#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Penrose Tiling: aperiodic tiling with golden ratio relationships using de Bruijn's method

[[ stitchable ]]
half4 penroseTilingEffect(
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

    // Slow rotation of the entire pattern
    float rot = t * 0.05;
    float ca = cos(rot), sa = sin(rot);
    float2 rp = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    // de Bruijn's pentagrid method for Penrose tiling
    // 5 families of parallel lines at 72-degree angles
    float scale = 3.0 + 0.3 * sin(t * 0.15);
    float2 sp = rp * scale;

    // Golden ratio
    float phi = (1.0 + sqrt(5.0)) * 0.5;

    // 5 grid directions
    float2 dirs[5];
    float gridVals[5];
    float gridFracs[5];

    for (int i = 0; i < 5; i++) {
        float a = float(i) * M_PI_F * 2.0 / 5.0;
        dirs[i] = float2(cos(a), sin(a));
        // Project point onto each direction, offset by golden ratio
        float proj = dot(sp, dirs[i]) + float(i) * phi * 0.1;
        gridVals[i] = proj;
        gridFracs[i] = fract(proj);
    }

    // Find the closest grid lines for edge detection
    float minEdgeDist = 10.0;
    for (int i = 0; i < 5; i++) {
        float edgeDist = min(gridFracs[i], 1.0 - gridFracs[i]);
        minEdgeDist = min(minEdgeDist, edgeDist);
    }

    // Tile edges: bright lines where any grid line is close
    float edges = smoothstep(0.06, 0.0, minEdgeDist);

    // Tile type identification: sum of floor values mod 2 determines kite vs dart
    float tileSum = 0.0;
    for (int i = 0; i < 5; i++) {
        tileSum += floor(gridVals[i]);
    }
    float tileType = fmod(abs(tileSum), 5.0);

    // Each tile type gets different internal pattern
    float tileFill = 0.0;

    // Use the fractional parts to create local coordinates within each tile
    float2 tileLocal = float2(gridFracs[0], gridFracs[1]);

    if (tileType < 1.5) {
        // Kite: star pattern inside
        float starAngle = atan2(tileLocal.y - 0.5, tileLocal.x - 0.5);
        float starR = length(tileLocal - 0.5);
        float star = cos(starAngle * 5.0) * 0.3 + 0.3;
        tileFill = smoothstep(0.02, 0.0, abs(starR - star)) * 0.2;
        tileFill += smoothstep(star * 1.2, 0.0, starR) * 0.05;
    } else if (tileType < 2.5) {
        // Dart: golden spiral approximation
        float spiralR = length(tileLocal - 0.5);
        float spiralA = atan2(tileLocal.y - 0.5, tileLocal.x - 0.5);
        float spiral = fract(spiralA / (2.0 * M_PI_F) + log(spiralR + 0.001) * phi);
        tileFill = smoothstep(0.1, 0.0, abs(spiral - 0.5)) * 0.15;
    } else if (tileType < 3.5) {
        // Rhombus: diagonal cross
        float cross = min(abs(tileLocal.x - tileLocal.y), abs(tileLocal.x + tileLocal.y - 1.0));
        tileFill = smoothstep(0.06, 0.0, cross) * 0.15;
    } else {
        // Pentagon seed: concentric pentagons
        float pr = length(tileLocal - 0.5);
        float pa = atan2(tileLocal.y - 0.5, tileLocal.x - 0.5);
        float pent = cos(M_PI_F / 5.0) / cos(fmod(pa + M_PI_F / 5.0, 2.0 * M_PI_F / 5.0) - M_PI_F / 5.0);
        tileFill = smoothstep(0.02, 0.0, abs(pr - pent * 0.3)) * 0.2;
        tileFill += smoothstep(0.015, 0.0, abs(pr - pent * 0.15)) * 0.12;
    }

    // Vertex stars: where 5 tiles meet (Penrose vertex configurations)
    float vertexGlow = 0.0;
    for (int i = 0; i < 5; i++) {
        float vDist = min(gridFracs[i], 1.0 - gridFracs[i]);
        int closeCount = 0;
        for (int j = 0; j < 5; j++) {
            if (j == i) continue;
            float vd2 = min(gridFracs[j], 1.0 - gridFracs[j]);
            if (vd2 < 0.12) closeCount++;
        }
        if (closeCount >= 2) {
            vertexGlow += smoothstep(0.08, 0.0, vDist) * 0.08;
        }
    }

    // Golden ratio wave: phi-based interference
    float phiWave = sin(dot(sp, dirs[0]) * phi * 2.0 - t * 1.0);
    phiWave *= sin(dot(sp, dirs[2]) * phi * 2.0 + t * 0.8);
    phiWave = abs(phiWave);
    float goldenGlow = smoothstep(0.0, 0.5, phiWave) * 0.06;

    // Pulsing energy along edges
    float edgePulse = sin(minEdgeDist * 100.0 - t * 3.0) * 0.5 + 0.5;
    float edgeEnergy = edges * edgePulse * 0.1;

    lum = edges * 0.3 + tileFill + vertexGlow + goldenGlow + edgeEnergy;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
