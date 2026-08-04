#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Breath of God: expanding/contracting fractal breath - creation and dissolution cycles

[[ stitchable ]]
half4 breathOfGodEffect(
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

    // The cosmic breath: slow inhalation and exhalation cycle
    float breathCycle = sin(t * 0.3) * 0.5 + 0.5; // 0=contracted, 1=expanded
    float breathScale = 0.6 + breathCycle * 0.8;

    float2 bp = p / breathScale;
    float r = length(bp);
    float angle = atan2(bp.y, bp.x);

    // Iterative fractal breath: folding space with each breath
    float2 z = bp * 3.0;
    float fractalLum = 0.0;

    for (int i = 0; i < 8; i++) {
        float fi = float(i);

        // Breath-modulated folding: more unfolded during expansion
        float foldOffset = mix(1.2, 0.5, breathCycle) - 0.05 * sin(t * 0.4 + fi * 0.5);
        z = abs(z) - foldOffset;

        // Rotation changes with breath phase
        float rotSpeed = mix(0.3, 0.1, breathCycle);
        float foldAngle = t * rotSpeed + fi * 0.35 + breathCycle * 0.5;
        float fca = cos(foldAngle), fsa = sin(foldAngle);
        z = float2(z.x * fca - z.y * fsa, z.x * fsa + z.y * fca);

        // Scale: expand during inhalation, contract during exhalation
        float scaleF = mix(1.3, 1.1, breathCycle);
        z *= scaleF;

        // Accumulate fold structure
        float foldEdge = min(abs(z.x), abs(z.y));
        fractalLum += smoothstep(0.15, 0.0, foldEdge) / (1.0 + fi * 0.5);

        // Creation sparks at fold points during expansion
        float spark = smoothstep(0.2, 0.0, length(fract(z * 0.3) - 0.5));
        fractalLum += spark * breathCycle * 0.05 / (1.0 + fi * 0.3);
    }

    lum += fractalLum * 0.35;

    // Breath waves: ripples emanating from/returning to center
    float breathDir = cos(t * 0.3); // positive=exhale, negative=inhale
    for (int w = 0; w < 5; w++) {
        float fw = float(w);
        float waveR = fw * 0.15 + t * breathDir * 0.3;
        waveR = fmod(waveR + 5.0, 1.5); // wrap
        float waveDist = abs(r - waveR);
        float wave = smoothstep(0.02, 0.0, waveDist);
        wave *= smoothstep(1.5, 0.0, waveR); // fade at edges
        lum += wave * 0.08;
    }

    // Sacred geometry emerges during full expansion
    float sacredGeo = 0.0;
    float geoOpacity = smoothstep(0.6, 1.0, breathCycle); // only visible when expanded

    if (geoOpacity > 0.01) {
        // Hexagonal lattice
        for (int i = 0; i < 6; i++) {
            float a = float(i) * M_PI_F / 3.0;
            float2 dir = float2(cos(a), sin(a));
            float proj = abs(fract(dot(bp * 4.0, dir)) - 0.5);
            sacredGeo += smoothstep(0.05, 0.0, proj);
        }
        sacredGeo *= geoOpacity * 0.06;
    }
    lum += sacredGeo;

    // Dissolution particles during contraction
    float dissolution = 0.0;
    float disOpacity = smoothstep(0.4, 0.0, breathCycle); // only visible when contracted

    if (disOpacity > 0.01) {
        float2 dp = bp * 6.0;
        float2 cellId = floor(dp);
        float2 cellF = fract(dp) - 0.5;

        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float2 id = cellId + float2(float(dx), float(dy));
                float h = hash21(id);
                float2 particleOff = hash22(id) - 0.5;
                // Particles scatter outward during dissolution
                float scatter = (1.0 - breathCycle) * 0.3;
                float2 scattered = particleOff * (1.0 + scatter) + float2(sin(t + h * 6.28), cos(t * 0.8 + h * 6.28)) * scatter;
                float d = length(cellF - scattered);
                dissolution += smoothstep(0.04, 0.0, d) * h;
            }
        }
        dissolution *= disOpacity * 0.15;
    }
    lum += dissolution;

    // Central divine light: brightest at the moment between breaths
    float betweenBreaths = 1.0 - abs(breathCycle - 0.5) * 2.0;
    float divineLight = smoothstep(0.3, 0.0, r) * betweenBreaths * 0.3;

    // Radiance at peak expansion
    float radiance = 0.0;
    if (breathCycle > 0.7) {
        float rayCount = 12.0;
        float rays = cos(angle * rayCount + t * 0.5);
        rays = smoothstep(0.5, 1.0, rays);
        radiance = rays * exp(-r * 2.0) * (breathCycle - 0.7) * 0.8;
    }

    lum += divineLight + radiance;

    // Domain-warped background field
    float2 warpBg = float2(
        simplex2d(p * 2.0 + float2(t * 0.15, 0.0)),
        simplex2d(p * 2.0 + float2(0.0, t * 0.12))
    );
    float bgField = fbm(p * 3.0 + warpBg * 0.3, t * 0.1);
    bgField = smoothstep(-0.2, 0.4, bgField) * 0.06;
    lum += bgField;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
