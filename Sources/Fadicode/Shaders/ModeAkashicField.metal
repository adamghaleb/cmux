#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Akashic Field: information field with flowing data streams forming interference patterns like cosmic memory

[[ stitchable ]]
half4 akashicFieldEffect(
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

    // Multiple data stream layers flowing in different directions
    for (int stream = 0; stream < 6; stream++) {
        float fs = float(stream);
        float streamAngle = fs * M_PI_F / 3.0 + t * 0.03;
        float2 streamDir = float2(cos(streamAngle), sin(streamAngle));
        float2 streamPerp = float2(-streamDir.y, streamDir.x);

        // Project onto stream coordinates
        float along = dot(p, streamDir);
        float across = dot(p, streamPerp);

        // Data packets: periodic pulses along the stream
        float packetFreq = 8.0 + fs * 3.0;
        float packetSpeed = 1.5 + fs * 0.3;
        float packet = sin(along * packetFreq - t * packetSpeed + fs * 2.0);
        packet = smoothstep(0.6, 1.0, packet); // sharp packet edges

        // Stream width modulated by noise
        float streamWidth = 0.03 + 0.01 * simplex2d(float2(along * 2.0, t * 0.3 + fs * 5.0));
        float inStream = smoothstep(streamWidth, streamWidth * 0.3, abs(across));

        // Data density: binary-like pattern
        float2 dataCoord = float2(along * 4.0 - t * packetSpeed * 0.5, across * 20.0);
        float dataHash = hash21(floor(dataCoord));
        float dataBit = step(0.5, dataHash) * smoothstep(0.4, 0.6, fract(dataCoord.x));
        dataBit *= inStream;

        lum += (packet * inStream * 0.08 + dataBit * 0.04) / (1.0 + fs * 0.2);
    }

    // Information nexus points: where multiple streams converge
    float nexus = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 nexusPos = float2(
            sin(t * 0.12 + fi * 1.256) * 0.4,
            cos(t * 0.1 + fi * 1.884) * 0.35
        );
        float d = length(p - nexusPos);
        float ang = atan2(p.y - nexusPos.y, p.x - nexusPos.x);

        // Nexus core
        float core = smoothstep(0.06, 0.0, d) * 0.3;

        // Information radiating outward in structured beams
        float beams = sin(ang * 8.0 + t * 2.0 + fi) * 0.5 + 0.5;
        beams *= exp(-d * 5.0) * 0.12;

        // Memory rings: concentric ripples of stored information
        for (int ring = 1; ring <= 4; ring++) {
            float ringR = float(ring) * 0.04 + 0.02 * sin(t * 0.5 + fi + float(ring));
            float ringGlow = smoothstep(0.008, 0.0, abs(d - ringR));
            float ringData = step(0.3, sin(ang * (4.0 + float(ring) * 2.0) + t + fi));
            nexus += ringGlow * ringData * 0.08;
        }

        nexus += core + beams;
    }
    lum += nexus;

    // Interference field: overlapping wave functions creating standing patterns
    float interference = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float waveAngle = fi * M_PI_F / 4.0 + t * 0.05;
        float2 waveDir = float2(cos(waveAngle), sin(waveAngle));
        float wave = sin(dot(p, waveDir) * 15.0 - t * 1.5 + fi * 1.0);
        interference += wave;
    }
    interference /= 4.0;
    float interferencePat = smoothstep(0.1, 0.0, abs(interference));
    lum += interferencePat * 0.12;

    // Akashic records: persistent holographic patterns (FBM-based)
    float2 warp = float2(
        fbm(p * 2.0 + float2(0.0, t * 0.1), t * 0.15),
        fbm(p * 2.0 + float2(5.0, t * 0.12), t * 0.15)
    );
    float records = fbm(p * 3.0 + warp * 0.4, t * 0.1);
    records = smoothstep(-0.2, 0.3, records) * 0.08;
    lum += records;

    // Universal grid: faint underlying lattice
    float2 gridP = p * 8.0;
    float gx = smoothstep(0.06, 0.0, abs(fract(gridP.x) - 0.5));
    float gy = smoothstep(0.06, 0.0, abs(fract(gridP.y) - 0.5));
    float universalGrid = max(gx, gy) * 0.04;
    // Grid nodes glow
    float2 gridNode = fract(gridP) - 0.5;
    float nodeDist = length(gridNode);
    universalGrid += smoothstep(0.08, 0.0, nodeDist) * 0.03;
    lum += universalGrid;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
