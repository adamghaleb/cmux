#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Geometric Alchemy: transmuting shapes - triangles morph to hexagons to circles in tessellated grid

[[ stitchable ]]
half4 geometricAlchemyEffect(
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
    float t = time * 0.22;
    float2 p = s.centered;

    float lum = 0.0;

    // Domain warp the space alchemically
    float2 warp = float2(
        simplex2d(p * 2.0 + float2(t * 0.2, 0.0)),
        simplex2d(p * 2.0 + float2(0.0, t * 0.25))
    );
    float2 wp = p + warp * 0.15;

    // Hexagonal grid tiling
    float scale = 4.0;
    float2 gp = wp * scale;

    // Hexagonal coordinate conversion
    float2 hexA = float2(1.0, 0.0);
    float2 hexB = float2(0.5, 0.866);
    float2 hexCoord = float2(
        dot(gp, float2(1.0, -1.0 / 1.732)),
        dot(gp, float2(0.0, 2.0 / 1.732))
    );

    float2 cellId = floor(hexCoord);
    float2 cellFrac = fract(hexCoord) - 0.5;

    // Per-cell properties
    float cellHash = hash21(cellId);
    float cellPhase = cellHash * 6.28;

    // Transmutation cycle: triangle -> square -> pentagon -> hexagon -> circle
    float morphCycle = fract(t * 0.15 + cellHash * 0.5);
    float sides = 3.0 + morphCycle * 9.0; // 3 to 12 sides (circle approx)

    // Per-cell rotation
    float rot = t * 0.3 * (cellHash > 0.5 ? 1.0 : -1.0) + cellPhase;
    float ca = cos(rot), sa = sin(rot);
    float2 rc = float2(cellFrac.x * ca - cellFrac.y * sa, cellFrac.x * sa + cellFrac.y * ca);

    // N-gon distance field
    float angle = atan2(rc.y, rc.x);
    float radius = length(rc);
    float ngon = cos(M_PI_F / sides) / cos(fmod(angle + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);

    // Breathing scale
    float breathe = 0.3 + 0.05 * sin(t * 0.8 + cellPhase);
    float shape = smoothstep(0.02, 0.0, radius - ngon * breathe);
    float edge = smoothstep(0.04, 0.01, abs(radius - ngon * breathe));

    // Inner sacred geometry: nested shapes at half scale
    float innerSides = max(3.0, sides - 2.0);
    float innerNgon = cos(M_PI_F / innerSides) / cos(fmod(angle - rot * 0.5 + M_PI_F / innerSides, 2.0 * M_PI_F / innerSides) - M_PI_F / innerSides);
    float innerEdge = smoothstep(0.03, 0.0, abs(radius - innerNgon * breathe * 0.5));

    // Second inner layer
    float inner2Sides = max(3.0, sides + 1.0);
    float inner2Ngon = cos(M_PI_F / inner2Sides) / cos(fmod(angle + rot * 0.3 + M_PI_F / inner2Sides, 2.0 * M_PI_F / inner2Sides) - M_PI_F / inner2Sides);
    float inner2Edge = smoothstep(0.025, 0.0, abs(radius - inner2Ngon * breathe * 0.25));

    // Alchemical glow: radiating lines from center
    float rays = sin(angle * sides + t * 2.0) * 0.5 + 0.5;
    rays *= smoothstep(breathe, 0.0, radius) * 0.3;

    // Inter-cell connection filaments (Voronoi edges)
    float edgeDist = min(abs(cellFrac.x), abs(cellFrac.y));
    float gridLines = smoothstep(0.05, 0.01, edgeDist);
    float filamentPulse = sin(t * 1.5 + cellHash * 6.28) * 0.3 + 0.7;
    gridLines *= filamentPulse * 0.15;

    // Transmutation glow: bright flash when shape changes whole-number sides
    float sidesFrac = fract(sides);
    float transmutFlash = smoothstep(0.1, 0.0, sidesFrac) + smoothstep(0.9, 1.0, sidesFrac);
    transmutFlash *= 0.15 * smoothstep(breathe * 1.5, 0.0, radius);

    lum = edge * 0.35 + innerEdge * 0.2 + inner2Edge * 0.15 + rays + gridLines + shape * 0.05 + transmutFlash;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
