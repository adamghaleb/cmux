#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Warp Tunnel: zooming through a tunnel with geometric cross-sections

[[ stitchable ]]
half4 warpTunnelEffect(
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

    float t = time * 0.3;
    float2 p = s.centered;
    float angle = atan2(p.y, p.x);

    // Tunnel coordinates: use 1/dist as depth
    float depth = 1.0 / (s.dist + 0.1);

    // Scrolling tunnel texture
    float tunnelU = angle / M_PI_F; // -1 to 1 around the tunnel
    float tunnelV = depth - t * 2.0; // scrolling into the tunnel

    // Grid pattern inside the tunnel
    float gridX = sin(tunnelU * 8.0 * M_PI_F) * 0.5 + 0.5;
    float gridY = sin(tunnelV * 6.0) * 0.5 + 0.5;
    float tunnelGrid = gridX * gridY;

    // Tunnel walls: brighter near edges (close to camera)
    float wallBright = smoothstep(0.3, 1.5, s.dist);

    // Speed lines radiating from center
    float speedLines = pow(abs(sin(angle * 16.0 + t)), 8.0);
    speedLines *= smoothstep(0.2, 0.8, s.dist);

    // Depth rings
    float rings = sin(depth * 4.0 - t * 6.0) * 0.5 + 0.5;
    rings *= wallBright;

    float lum = tunnelGrid * wallBright * 0.4 + speedLines * 0.3 + rings * 0.3;

    // Center glow (light at end of tunnel)
    lum += smoothstep(0.5, 0.0, s.dist) * 0.3;

    lum *= smoothstep(1.8, 0.3, s.dist);
    lum = clamp(lum, 0.0, 1.0);

    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
