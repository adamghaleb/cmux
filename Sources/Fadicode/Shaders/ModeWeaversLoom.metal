#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Weaver's Loom: geometric entities actively weaving reality — Machine Elves inspired.
// Two intersecting wave grids create loom-like interference fabric with Voronoi weavers
// at intersection points containing internal rotating geometry.

[[ stitchable ]]
half4 weaversLoomEffect(
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

    // --- Loom grid A: angled wave fabric ---
    float angleA = 0.35 + sin(t * 0.08) * 0.05;
    float caA = cos(angleA), saA = sin(angleA);
    float2 pA = float2(p.x * caA - p.y * saA, p.x * saA + p.y * caA);

    float warpFreqA = 12.0;
    float weftFreqA = 10.0;
    float warp_a = sin(pA.x * warpFreqA + t * 0.8 + simplex2d(pA * 2.0 + t * 0.1) * 1.5);
    float weft_a = sin(pA.y * weftFreqA - t * 0.6 + simplex2d(pA.yx * 2.0 + t * 0.12) * 1.2);
    float fabricA = abs(warp_a * weft_a);

    // --- Loom grid B: counter-angled wave fabric ---
    float angleB = -0.4 + cos(t * 0.06) * 0.05;
    float caB = cos(angleB), saB = sin(angleB);
    float2 pB = float2(p.x * caB - p.y * saB, p.x * saB + p.y * caB);

    float warpFreqB = 11.0;
    float weftFreqB = 9.0;
    float warp_b = sin(pB.x * warpFreqB - t * 0.7 + simplex2d(pB * 1.8 + t * 0.09) * 1.3);
    float weft_b = sin(pB.y * weftFreqB + t * 0.5 + simplex2d(pB.yx * 1.8 + t * 0.11) * 1.0);
    float fabricB = abs(warp_b * weft_b);

    // --- Moire interference where grids overlap ---
    float moire = abs(fabricA - fabricB);
    moire = smoothstep(0.0, 0.6, moire);
    lum += moire * 0.25;

    // Combined fabric structure
    float fabric = (fabricA + fabricB) * 0.5;
    fabric = smoothstep(0.1, 0.7, fabric);
    lum += fabric * 0.15;

    // Thread highlight lines (warp threads catch the light)
    float threadA = smoothstep(0.95, 1.0, abs(warp_a)) * smoothstep(0.3, 0.0, abs(weft_a));
    float threadB = smoothstep(0.95, 1.0, abs(warp_b)) * smoothstep(0.3, 0.0, abs(weft_b));
    lum += (threadA + threadB) * 0.15;

    // --- Voronoi weaver entities at intersection nodes ---
    float2 weaverGrid = p * 3.5;
    float2 weaverCellId = floor(weaverGrid);
    float2 weaverCellUv = fract(weaverGrid) - 0.5;

    float minWeaverDist = 10.0;
    float2 closestWeaverId = float2(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = weaverCellId + neighbor;
            float2 rnd = hash22(id);

            // Weavers sit near grid intersections but with slight offset
            float2 wpos = neighbor + (rnd - 0.5) * 0.4;
            wpos += 0.05 * float2(sin(t * 0.4 + rnd.x * 6.28), cos(t * 0.35 + rnd.y * 6.28));

            float wd = length(weaverCellUv - wpos);
            if (wd < minWeaverDist) {
                minWeaverDist = wd;
                closestWeaverId = id;
            }
        }
    }

    // Weaver entity body
    float weaverPhase = hash21(closestWeaverId) * 6.28;
    float weaverRot = t * (0.3 + hash21(closestWeaverId + 7.7) * 0.3) + weaverPhase;

    float weaverBody = smoothstep(0.18, 0.08, minWeaverDist);

    // Internal rotating geometry inside each weaver
    if (minWeaverDist < 0.18) {
        float2 wLocalP = weaverCellUv; // local coords around weaver
        float wAng = atan2(wLocalP.y, wLocalP.x) + weaverRot;
        float wR = minWeaverDist / 0.18;

        // Morphing polygon (3-6 sides based on hash)
        float sides = floor(3.0 + hash21(closestWeaverId + 3.3) * 4.0);
        float polygonDist = cos(M_PI_F / sides) /
                            cos(fmod(wAng + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);
        float innerShape = smoothstep(0.02, 0.0, wR - polygonDist * 0.7);

        // Spinning internal pattern
        float innerPattern = sin(wAng * sides * 2.0 + t * 1.5 + weaverPhase) * 0.5 + 0.5;
        innerPattern *= smoothstep(0.8, 0.0, wR);

        // Concentric rings inside weaver
        float rings = sin(wR * 25.0 - t * 2.0 + weaverPhase);
        rings = smoothstep(0.7, 1.0, abs(rings)) * smoothstep(0.8, 0.1, wR);

        lum += weaverBody * 0.25 + innerShape * 0.15 + innerPattern * 0.1 + rings * 0.08;
    } else {
        lum += weaverBody * 0.1;
    }

    // Weaver aura glow
    float weaverAura = smoothstep(0.3, 0.1, minWeaverDist);
    float auraPulse = sin(t * 0.8 + weaverPhase) * 0.2 + 0.8;
    lum += weaverAura * auraPulse * 0.1;

    // --- Connection threads between weavers ---
    // Use a separate Voronoi pass for edge detection (filaments)
    float2 edgeGrid = p * 3.5;
    float2 edgeCellId = floor(edgeGrid);
    float2 edgeCellUv = fract(edgeGrid) - 0.5;

    float md1 = 10.0, md2 = 10.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 id = edgeCellId + neighbor;
            float2 rnd = hash22(id);
            float2 epos = neighbor + (rnd - 0.5) * 0.4;
            epos += 0.05 * float2(sin(t * 0.4 + rnd.x * 6.28), cos(t * 0.35 + rnd.y * 6.28));
            float ed = length(edgeCellUv - epos);
            if (ed < md1) { md2 = md1; md1 = ed; }
            else if (ed < md2) { md2 = ed; }
        }
    }
    float connectionLine = smoothstep(0.06, 0.0, md2 - md1);
    float connectionPulse = sin(t * 1.2 + (md1 + md2) * 15.0) * 0.3 + 0.7;
    lum += connectionLine * connectionPulse * 0.2;

    // --- FBM life overlay ---
    float organic = fbm(p * 3.0, t * 0.2);
    organic = smoothstep(-0.15, 0.2, organic);
    lum += organic * 0.05;

    lum *= smoothstep(1.7, 0.15, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
