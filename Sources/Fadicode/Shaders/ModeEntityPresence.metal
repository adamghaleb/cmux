#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Entity Presence: semi-transparent glowing beings that breathe and pulse

[[ stitchable ]]
half4 entityPresenceEffect(
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

    // 3 entity beings at different positions
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float phase = fi * 2.094; // 120 degrees apart

        // Entity center drifts in slow orbit
        float2 center = float2(
            sin(t * 0.2 + phase) * 0.35,
            cos(t * 0.15 + phase * 1.2) * 0.3
        );

        float2 diff = p - center;
        float d = length(diff);
        float ang = atan2(diff.y, diff.x);

        // Entity body: organic shape using noise-modulated distance
        float bodyNoise = simplex2d(float2(ang * 2.0 / M_PI_F, t * 0.3 + fi * 5.0));
        float bodyRadius = 0.2 + 0.05 * bodyNoise + 0.02 * sin(t * 0.8 + fi);
        float body = smoothstep(bodyRadius, bodyRadius * 0.3, d);

        // Aura: multiple concentric rings of light
        float aura = 0.0;
        for (int ring = 1; ring <= 4; ring++) {
            float ringDist = bodyRadius + float(ring) * 0.06;
            float ringWidth = 0.015 + float(ring) * 0.005;
            float pulse = sin(t * (1.0 + fi * 0.3) - float(ring) * 0.5) * 0.3 + 0.7;
            aura += smoothstep(ringWidth, 0.0, abs(d - ringDist)) * pulse / float(ring);
        }

        // Internal sacred geometry: rotating pattern inside the entity
        float innerGeom = 0.0;
        if (d < bodyRadius) {
            float innerAng = ang + t * 0.5 * (1.0 + fi * 0.2);
            float innerR = d / bodyRadius;
            innerGeom = sin(innerAng * 6.0 + innerR * 10.0) * 0.5 + 0.5;
            innerGeom *= sin(innerAng * 3.0 - t * 1.5) * 0.5 + 0.5;
            innerGeom *= body;
        }

        // Eye-like central point
        float eye = smoothstep(0.04, 0.0, d - 0.01) * (sin(t * 0.5 + fi) * 0.3 + 0.7);

        lum += body * 0.25 + aura * 0.2 + innerGeom * 0.15 + eye * 0.2;
    }

    // Connecting field between entities
    float field = fbm(p * 3.0, t * 0.3);
    field = smoothstep(-0.1, 0.2, field);
    lum += field * 0.05;

    lum *= smoothstep(1.8, 0.1, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
