#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Infinite Zoom: recursive zoom into self-similar pattern (Droste effect)

[[ stitchable ]]
half4 infiniteZoomEffect(
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

    // Log-polar transform for infinite zoom
    float r = length(p);
    float angle = atan2(p.y, p.x);

    // Continuous zoom: use log(r) as the "depth" coordinate
    float logR = log(max(r, 0.001));
    float zoomSpeed = t * 0.8;

    // Create self-similar layers by repeating in log-space
    float layerRepeat = 1.2;
    float depth = fract((logR + zoomSpeed) / layerRepeat);
    float layerIndex = floor((logR + zoomSpeed) / layerRepeat);

    // Per-layer rotation
    float layerRot = layerIndex * 0.5 + t * 0.1;
    float layerAngle = angle + layerRot;

    // Self-similar pattern: hexagonal lattice at each scale
    float layerScale = exp(depth * layerRepeat);
    float2 tp = float2(layerAngle / (2.0 * M_PI_F), depth) * 6.0;

    // Hexagonal grid in the unwrapped space
    float2 hexP = tp;
    float2 hexId = floor(hexP);
    float2 hexF = fract(hexP) - 0.5;
    float hexHash = hash21(hexId + layerIndex * 13.0);

    // Geometric motif in each cell
    float motifAngle = atan2(hexF.y, hexF.x) + hexHash * 6.28;
    float motifR = length(hexF);
    float sides = 3.0 + floor(hexHash * 4.0) * 2.0; // 3, 5, 7, 9
    float ngon = cos(M_PI_F / sides) / cos(fmod(motifAngle + M_PI_F / sides, 2.0 * M_PI_F / sides) - M_PI_F / sides);

    float shape = smoothstep(0.02, 0.0, motifR - ngon * 0.35);
    float edge = smoothstep(0.03, 0.0, abs(motifR - ngon * 0.35));

    // Inner detail: concentric scaled copies
    float innerEdge = smoothstep(0.02, 0.0, abs(motifR - ngon * 0.2));
    float innerEdge2 = smoothstep(0.015, 0.0, abs(motifR - ngon * 0.1));

    // Spiral arms connecting layers
    float spiralCount = 5.0;
    float spiral = sin(layerAngle * spiralCount + logR * 10.0 - t * 3.0);
    float spiralLine = smoothstep(0.3, 0.0, abs(spiral)) * 0.12;
    spiralLine *= smoothstep(0.0, 0.1, r) * smoothstep(1.2, 0.3, r);

    // Radial structures
    float radial = sin(layerAngle * 12.0 + layerIndex * 2.0);
    float radialLine = smoothstep(0.4, 0.0, abs(radial)) * 0.08;
    radialLine *= exp(-abs(depth - 0.5) * 4.0); // fade between layers

    // Layer transition glow
    float transGlow = smoothstep(0.1, 0.0, depth) + smoothstep(0.9, 1.0, depth);
    transGlow *= 0.1;

    // Fractal boundary: the edge where zoom repeats
    float boundary = smoothstep(0.05, 0.0, abs(depth - 0.0));
    boundary += smoothstep(0.05, 0.0, abs(depth - 1.0));
    boundary *= 0.15;

    // Accumulate pattern from multiple depth samples for richness
    float multiDepth = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float dOff = fi * 0.3;
        float d2 = fract((logR + zoomSpeed + dOff) / layerRepeat);
        float lIdx2 = floor((logR + zoomSpeed + dOff) / layerRepeat);
        float a2 = angle + lIdx2 * 0.5 + t * 0.1;
        float2 tp2 = float2(a2 / (2.0 * M_PI_F), d2) * 6.0;
        float2 hf2 = fract(tp2) - 0.5;
        float mr2 = length(hf2);
        float ma2 = atan2(hf2.y, hf2.x);
        float ng2 = cos(M_PI_F / 6.0) / cos(fmod(ma2 + M_PI_F / 6.0, M_PI_F / 3.0) - M_PI_F / 6.0);
        multiDepth += smoothstep(0.03, 0.0, abs(mr2 - ng2 * 0.3)) * 0.08;
    }

    lum = edge * 0.3 + innerEdge * 0.15 + innerEdge2 * 0.1 + shape * 0.05 + spiralLine + radialLine + transGlow + boundary + multiDepth;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
