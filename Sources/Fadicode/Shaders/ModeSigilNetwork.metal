#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Sigil Network: hexagonal grid of connected sigils — each hex cell contains
// a unique rotating sacred symbol, connected by pulsing luminous pathways

[[ stitchable ]]
half4 sigilNetworkEffect(
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

    // --- Hexagonal grid setup ---
    // Convert to hex coordinates
    float hexScale = 4.0;
    float2 hp = p * hexScale;

    // Hex grid: offset columns
    float2 hexSize = float2(1.732, 1.0); // sqrt(3), 1
    float2 halfHex = hexSize * 0.5;

    float2 a = fmod(hp + 1000.0, hexSize) - halfHex;
    float2 b = fmod(hp + halfHex + 1000.0, hexSize) - halfHex;

    float2 gv;
    float2 cellId;
    if (length(a) < length(b)) {
        gv = a;
        cellId = floor((hp + 1000.0) / hexSize);
    } else {
        gv = b;
        cellId = floor((hp + halfHex + 1000.0) / hexSize);
    }

    float cellDist = length(gv);
    float cellAng = atan2(gv.y, gv.x);

    // --- Hex cell edge glow (network lines) ---
    float hexEdge = smoothstep(0.48, 0.42, cellDist / 0.577);
    float edgeGlow = smoothstep(0.42, 0.48, cellDist / 0.577) *
                     smoothstep(0.52, 0.48, cellDist / 0.577);

    // Pulse along edges in sequence
    float edgePulse = sin(t * 1.0 + hash21(cellId) * 6.28 + cellAng * 2.0) * 0.3 + 0.7;
    lum += edgeGlow * edgePulse * 0.35;

    // --- Sacred symbol inside each cell ---
    float cellHash = hash21(cellId);
    float cellHash2 = hash21(cellId + 17.3);

    // Symbol type: triangle(3), square(4), pentagon(5), hexagon(6)
    float sides = floor(3.0 + cellHash * 4.0); // 3, 4, 5, or 6

    // Per-cell rotation
    float symbolRot = t * (0.2 + cellHash2 * 0.3) + cellHash * 6.28;
    float rotAng = cellAng + symbolRot;

    // Polygon distance function
    float polyDist = cos(M_PI_F / sides) /
                     cos(fmod(rotAng + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);

    float symbolRadius = 0.25 + 0.03 * sin(t * 0.6 + cellHash * 6.28);
    float normalizedR = cellDist / symbolRadius;

    // Symbol outline
    float symbolOutline = smoothstep(0.03, 0.0, abs(normalizedR - polyDist * 0.8));
    lum += symbolOutline * hexEdge * 0.35;

    // Inner concentric polygon (scaled down)
    float innerPoly = smoothstep(0.03, 0.0, abs(normalizedR - polyDist * 0.45));
    float innerPulse = sin(t * 0.8 + cellHash * 6.28) * 0.3 + 0.7;
    lum += innerPoly * hexEdge * innerPulse * 0.2;

    // Vertex points of the polygon (bright dots at corners)
    for (int v = 0; v < 6; v++) {
        if (float(v) >= sides) break;
        float vAng = float(v) * 2.0 * M_PI_F / sides + symbolRot;
        float2 vtx = float2(cos(vAng), sin(vAng)) * symbolRadius * 0.65;
        float vDist = length(gv - vtx);
        float vGlow = smoothstep(0.05, 0.0, vDist);
        float vPulse = sin(t * 1.2 + float(v) * 1.047 + cellHash * 3.0) * 0.25 + 0.75;
        lum += vGlow * vPulse * 0.2;
    }

    // Radial lines from center to vertices (spokes)
    float spokes = abs(sin(rotAng * sides));
    spokes = smoothstep(0.96, 1.0, spokes);
    float spokeMask = smoothstep(0.0, 0.05, cellDist) * smoothstep(symbolRadius * 0.7, symbolRadius * 0.3, cellDist);
    lum += spokes * spokeMask * hexEdge * 0.15;

    // Central dot
    float centerDot = smoothstep(0.04, 0.0, cellDist);
    float centerPulse = sin(t * 0.5 + cellHash * 6.28) * 0.2 + 0.8;
    lum += centerDot * centerPulse * 0.25;

    // --- Connection lines between adjacent cells (bright pulses traveling) ---
    // Use Voronoi edge detection for inter-cell connections
    float md1 = 10.0, md2 = 10.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 off = float2(float(dx), float(dy));
            float2 id = cellId + off;
            float2 rnd = hash22(id);
            float2 neighborPos = off + (rnd - 0.5) * 0.0; // hex centers, no randomness
            float d = length(gv / 0.577 - neighborPos);
            if (d < md1) { md2 = md1; md1 = d; }
            else if (d < md2) { md2 = d; }
        }
    }
    float networkLine = smoothstep(0.08, 0.0, md2 - md1);
    float networkPulse = sin(t * 1.5 + (md1 * 10.0)) * 0.3 + 0.7;
    lum += networkLine * networkPulse * 0.12;

    // --- Activation wave: circular pulse expanding outward ---
    float waveRadius = fract(t * 0.1) * 3.0;
    float activationWave = smoothstep(0.15, 0.0, abs(s.dist - waveRadius));
    lum += activationWave * 0.15;

    // --- FBM organic overlay for life ---
    float organic = fbm(p * 3.5, t * 0.2);
    organic = organic * 0.5 + 0.5;
    lum += organic * 0.06;

    // Subtle energy field between symbols
    float energy = simplex2d(p * 8.0 + float2(t * 0.15, t * 0.12));
    energy = smoothstep(0.3, 0.6, abs(energy));
    lum += energy * 0.04;

    lum *= smoothstep(1.7, 0.15, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
