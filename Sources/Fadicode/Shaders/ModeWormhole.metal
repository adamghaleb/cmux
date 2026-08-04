#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Wormhole: twin vortex singularities connected by warped spacetime bridge

[[ stitchable ]]
half4 wormholeEffect(
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

    // Two singularity positions orbiting each other
    float orbitR = 0.35 + 0.1 * sin(t * 0.3);
    float2 sing1 = float2(cos(t * 0.2), sin(t * 0.2)) * orbitR;
    float2 sing2 = -sing1;

    // Gravitational lensing: warp space around singularities
    float2 warped = p;
    for (int i = 0; i < 2; i++) {
        float2 singPos = (i == 0) ? sing1 : sing2;
        float2 diff = warped - singPos;
        float d = length(diff);
        float strength = 0.08 / (d * d + 0.01);
        // Spiral inward: mix attraction with rotation
        float2 attract = -normalize(diff) * strength;
        float2 spin = float2(-diff.y, diff.x) / (d + 0.01) * strength * 0.5;
        warped += attract + spin;
    }

    // Accretion disk around each singularity
    for (int i = 0; i < 2; i++) {
        float2 singPos = (i == 0) ? sing1 : sing2;
        float fi = float(i);
        float2 diff = p - singPos;
        float d = length(diff);
        float ang = atan2(diff.y, diff.x);

        // Disk: ring structure with spiral arms
        float diskR = 0.18 + 0.03 * sin(t + fi * 3.14);
        for (int ring = 0; ring < 5; ring++) {
            float ringR = diskR * (0.4 + float(ring) * 0.15);
            float ringWidth = 0.008 + float(ring) * 0.003;
            float spiral = ang + d * 8.0 * (i == 0 ? 1.0 : -1.0) - t * 3.0 * (i == 0 ? 1.0 : -1.0);
            float brightness = sin(spiral * 3.0) * 0.4 + 0.6;
            float ringGlow = smoothstep(ringWidth, 0.0, abs(d - ringR)) * brightness;
            lum += ringGlow * 0.15 / (1.0 + float(ring) * 0.3);
        }

        // Event horizon glow
        float horizon = smoothstep(0.06, 0.0, d) * 0.4;
        // Hawking radiation: tiny bright sparks near horizon
        float hawking = smoothstep(0.08, 0.04, d) * smoothstep(0.02, 0.04, d);
        hawking *= (sin(ang * 12.0 + t * 8.0 + fi * 3.14) * 0.5 + 0.5);
        lum += horizon + hawking * 0.15;
    }

    // Spacetime bridge (Einstein-Rosen bridge) connecting the two
    float2 bridgeDir = normalize(sing2 - sing1);
    float2 bridgePerp = float2(-bridgeDir.y, bridgeDir.x);
    float bridgeLen = length(sing2 - sing1);

    float2 bridgeLocal = float2(
        dot(p - sing1, bridgeDir),
        dot(p - sing1, bridgePerp)
    );

    float tParam = bridgeLocal.x / bridgeLen;
    if (tParam > 0.0 && tParam < 1.0) {
        // Bridge throat: narrows in the middle
        float throatWidth = 0.06 + 0.04 * (4.0 * tParam * (1.0 - tParam));
        float bridgeDist = abs(bridgeLocal.y) - throatWidth;

        // Warped spacetime grid lines along the bridge
        float gridU = sin(tParam * 30.0 - t * 5.0) * 0.5 + 0.5;
        float gridV = sin(bridgeLocal.y * 40.0 + t * 2.0) * 0.5 + 0.5;
        float bridgeGrid = gridU * gridV;

        float bridgeGlow = smoothstep(0.02, 0.0, bridgeDist);
        float bridgeEdge = smoothstep(0.01, 0.0, abs(bridgeDist));
        lum += bridgeGlow * bridgeGrid * 0.15 + bridgeEdge * 0.25;
    }

    // Background: warped spacetime grid
    float2 gridP = warped * 5.0;
    float gridX = smoothstep(0.06, 0.0, abs(fract(gridP.x) - 0.5));
    float gridY = smoothstep(0.06, 0.0, abs(fract(gridP.y) - 0.5));
    float spacetimeGrid = max(gridX, gridY) * 0.08;

    // Gravitational wave ripples
    float gravWave = sin(s.dist * 20.0 - t * 4.0) * exp(-s.dist * 2.0) * 0.08;

    lum += spacetimeGrid + gravWave;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
