#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Electric Field: field lines between multiple charges with intensity at convergence points

[[ stitchable ]]
half4 electricFieldEffect(
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

    // 8 charges: alternating positive/negative, orbiting
    float2 charges[8];
    float signs[8];
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float orbitR = 0.25 + 0.15 * sin(fi * 1.2 + t * 0.1);
        float orbitAngle = fi * 0.785 + t * 0.15 * (1.0 + fi * 0.05);
        charges[i] = float2(cos(orbitAngle), sin(orbitAngle)) * orbitR;
        signs[i] = (int(fi) % 2 == 0) ? 1.0 : -1.0;
    }

    // Compute electric potential at this point
    float potential = 0.0;
    float2 fieldVec = float2(0.0);

    for (int i = 0; i < 8; i++) {
        float2 diff = p - charges[i];
        float d = length(diff);
        float dClamped = max(d, 0.03); // avoid singularity

        potential += signs[i] / dClamped;
        fieldVec += signs[i] * diff / (dClamped * dClamped * dClamped);
    }

    // Equipotential lines: where potential crosses integer values
    float potLines = sin(potential * 3.0);
    float equipotential = smoothstep(0.15, 0.0, abs(potLines));

    // Field line visualization using the stream function
    // Field lines are tangent to the field vector
    float fieldAngle = atan2(fieldVec.y, fieldVec.x);
    float fieldMag = length(fieldVec);

    // Create field line pattern by using angle as a periodic function
    float streamFunc = sin(fieldAngle * 8.0 - potential * 2.0);
    float fieldLines = smoothstep(0.2, 0.0, abs(streamFunc)) * smoothstep(0.0, 2.0, fieldMag);

    // Charge glow
    float chargeGlow = 0.0;
    for (int i = 0; i < 8; i++) {
        float d = length(p - charges[i]);
        // Core glow
        chargeGlow += smoothstep(0.04, 0.0, d) * 0.4;
        // Corona
        float corona = exp(-d * 15.0) * 0.2;
        corona *= 1.0 + 0.3 * sin(atan2(p.y - charges[i].y, p.x - charges[i].x) * 6.0 + t * 3.0);
        chargeGlow += corona;
    }

    // Electric arcs between opposite charges
    float arcs = 0.0;
    for (int i = 0; i < 8; i += 2) {
        float2 posCharge = charges[i];
        float2 negCharge = charges[i + 1];
        float2 arcDir = normalize(negCharge - posCharge);
        float2 arcPerp = float2(-arcDir.y, arcDir.x);
        float arcLen = length(negCharge - posCharge);

        float2 arcLocal = float2(
            dot(p - posCharge, arcDir),
            dot(p - posCharge, arcPerp)
        );

        float tParam = arcLocal.x / arcLen;
        if (tParam > 0.0 && tParam < 1.0) {
            // Arc path with noise displacement
            float arcNoise = simplex2d(float2(tParam * 8.0, t * 4.0 + float(i))) * 0.04;
            arcNoise += simplex2d(float2(tParam * 16.0, t * 6.0 + float(i) * 3.0)) * 0.02;
            float arcDist = abs(arcLocal.y - arcNoise);
            float arcBright = smoothstep(0.015, 0.0, arcDist);
            arcBright *= sin(tParam * M_PI_F); // fade at endpoints
            // Flickering
            arcBright *= 0.7 + 0.3 * sin(t * 12.0 + float(i) * 2.0);
            arcs += arcBright * 0.2;
        }
    }

    // Electromagnetic energy density glow
    float energyDensity = fieldMag * fieldMag;
    energyDensity = smoothstep(0.0, 15.0, energyDensity) * 0.08;

    lum = equipotential * 0.25 + fieldLines * 0.2 + chargeGlow + arcs + energyDensity;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
