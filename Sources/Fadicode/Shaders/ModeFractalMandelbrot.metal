#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Fractal Mandelbrot: animated zoom into the Mandelbrot set with rotating Julia set transitions

[[ stitchable ]]
half4 fractalMandelbrotEffect(
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

    // Zoom target: spiral into a mini-brot at the seahorse valley
    float2 target = float2(-0.7453, 0.1127);
    float zoom = 2.5 / (1.0 + t * 0.3);
    zoom = max(zoom, 0.0001);

    // Slowly rotate the view
    float rotAngle = t * 0.15;
    float ca = cos(rotAngle), sa = sin(rotAngle);
    float2 rp = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    // Morph between Mandelbrot and Julia set
    float juliaBlend = sin(t * 0.25) * 0.5 + 0.5;
    float2 juliaC = float2(
        -0.8 + 0.2 * sin(t * 0.18),
        0.156 + 0.1 * cos(t * 0.22)
    );

    float2 c = rp * zoom + target;
    float2 z = mix(float2(0.0), c, 1.0 - juliaBlend);
    float2 iterC = mix(c, juliaC, juliaBlend);

    // Mandelbrot / Julia iteration with orbit trap
    float lum = 0.0;
    float minOrbitDist = 10.0;
    float orbitAngle = 0.0;
    int maxIter = 64;
    int escaped = maxIter;

    for (int i = 0; i < 64; i++) {
        // z = z^2 + c
        float2 zNew = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + iterC;
        z = zNew;

        float d = length(z);
        if (d > 4.0) {
            escaped = i;
            break;
        }

        // Orbit traps: distance to origin, axes, and circle
        float trapCircle = abs(d - 1.0);
        float trapCross = min(abs(z.x), abs(z.y));
        float trapLine = abs(z.x + z.y) * 0.707;
        float trapDist = min(min(trapCircle, trapCross), trapLine);

        if (trapDist < minOrbitDist) {
            minOrbitDist = trapDist;
            orbitAngle = atan2(z.y, z.x);
        }
    }

    // Smooth escape-time coloring
    float smoothEscape = float(escaped) / float(maxIter);
    float escapeLum = 1.0 - smoothEscape;
    escapeLum = pow(escapeLum, 0.6);

    // Orbit trap luminance
    float trapLum = smoothstep(1.0, 0.0, minOrbitDist);
    trapLum *= 0.6 + 0.4 * sin(orbitAngle * 3.0 + t);

    // Interior detail for points that don't escape
    float interior = 0.0;
    if (escaped == maxIter) {
        interior = trapLum * 0.8;
        // Add fbm texture inside the set
        float detail = fbm(z * 2.0, t * 0.3) * 0.5 + 0.5;
        interior += detail * 0.2;
    }

    // Combine exterior escape-time with orbit traps
    lum = (escaped < maxIter) ? (escapeLum * 0.5 + trapLum * 0.5) : interior;

    // Add subtle edge glow at set boundary
    float edgeGlow = smoothstep(0.0, 0.15, smoothEscape) * smoothstep(0.3, 0.15, smoothEscape);
    lum += edgeGlow * 0.3;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
