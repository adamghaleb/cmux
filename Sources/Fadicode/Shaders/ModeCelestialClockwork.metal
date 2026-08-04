#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Celestial Clockwork: nested rotating gear-like rings with planetary orbit traces

[[ stitchable ]]
half4 celestialClockworkEffect(
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
    float r = length(p);
    float angle = atan2(p.y, p.x);

    // 7 nested gear rings
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float ringR = 0.12 + fi * 0.13;
        float ringWidth = 0.015 + fi * 0.003;
        float teeth = 8.0 + fi * 4.0; // more teeth on outer rings
        float speed = (0.3 - fi * 0.03) * ((int(fi) % 2 == 0) ? 1.0 : -1.0); // alternate directions
        float gearAngle = angle + t * speed;

        // Gear tooth profile
        float toothHeight = 0.015 + fi * 0.002;
        float toothProfile = sin(gearAngle * teeth) * toothHeight;
        float gearOuter = ringR + toothProfile;
        float gearInner = ringR - ringWidth;

        // Gear ring
        float ring = smoothstep(0.008, 0.0, abs(r - gearOuter));
        ring += smoothstep(0.005, 0.0, abs(r - gearInner));

        // Spokes connecting to inner ring
        float spokes = 0.0;
        if (r > gearInner - 0.02 && r < gearOuter + 0.02) {
            float spokeCount = teeth * 0.5;
            float spokeAngle = fmod(gearAngle * spokeCount + M_PI_F, 2.0 * M_PI_F) - M_PI_F;
            spokes = smoothstep(0.06, 0.0, abs(spokeAngle / spokeCount));
            spokes *= smoothstep(gearOuter + 0.02, gearOuter, r) * smoothstep(gearInner - 0.02, gearInner, r);
        }

        // Gear body fill with filigree
        float inGear = smoothstep(gearOuter + 0.005, gearOuter, r) * smoothstep(gearInner - 0.005, gearInner, r);
        float filigree = sin(gearAngle * teeth * 2.0 + r * 80.0) * 0.5 + 0.5;
        filigree *= sin(gearAngle * teeth * 0.5 - r * 40.0) * 0.5 + 0.5;
        filigree *= inGear * 0.08;

        lum += (ring * 0.2 + spokes * 0.08 + filigree) / (1.0 + fi * 0.15);
    }

    // Planetary bodies on orbital tracks
    for (int planet = 0; planet < 5; planet++) {
        float fp = float(planet);
        float orbitR = 0.2 + fp * 0.16;
        float orbitSpeed = 0.4 / (1.0 + fp * 0.5);
        float planetAngle = t * orbitSpeed + fp * 1.256;
        float2 planetPos = float2(cos(planetAngle), sin(planetAngle)) * orbitR;

        // Planet body
        float planetDist = length(p - planetPos);
        float planetSize = 0.015 + fp * 0.005;
        float planet_body = smoothstep(planetSize, 0.0, planetDist);

        // Orbit trail: fading arc behind the planet
        float trailAngle = angle - planetAngle;
        trailAngle = fmod(trailAngle + 3.0 * M_PI_F, 2.0 * M_PI_F) - M_PI_F;
        float trail = smoothstep(0.005, 0.0, abs(r - orbitR));
        trail *= smoothstep(-3.14, 0.0, trailAngle) * smoothstep(0.5, 0.0, trailAngle);

        // Moon for larger planets
        if (planet > 1) {
            float moonAngle = t * orbitSpeed * 3.0 + fp;
            float moonR = planetSize * 2.5;
            float2 moonPos = planetPos + float2(cos(moonAngle), sin(moonAngle)) * moonR;
            float moonDist = length(p - moonPos);
            lum += smoothstep(0.006, 0.0, moonDist) * 0.2;
        }

        lum += planet_body * 0.35 + trail * 0.1;
    }

    // Central orrery hub with emanating light
    float hub = smoothstep(0.06, 0.0, r);
    float hubDetail = sin(angle * 8.0 + t * 1.5) * 0.5 + 0.5;
    hub *= 0.3 + hubDetail * 0.15;
    lum += hub;

    // Zodiac markings on outermost ring
    float zodiacR = 0.95;
    float zodiacDist = abs(r - zodiacR);
    float zodiac = smoothstep(0.015, 0.0, zodiacDist);
    float zodiacMarks = step(0.95, cos(angle * 12.0));
    zodiac *= 0.1 + zodiacMarks * 0.1;
    lum += zodiac;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
