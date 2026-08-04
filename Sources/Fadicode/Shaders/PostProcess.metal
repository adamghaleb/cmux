#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "ShaderUtils.h"
using namespace metal;

// Post-process pass: palette-based coloring with multiple visual style presets.
// Applied as a layerEffect so it can sample at grid cell centers for pixelation.
// Input: grayscale luminance from the shader (after optional blur).
//
// presetMode selects the visual style:
//   0 = Pixel Grid   — square cells + grid lines + max-pool (original)
//   1 = Clean Pixel   — square cells, no grid lines, 4-level posterize
//   2 = Honeycomb     — hex grid cells + thin hex borders
//   3 = Halftone      — circular dots sized by brightness
//   4 = CRT           — scanlines + RGB sub-pixel separation
//   5 = Neon          — smooth palette + additive bloom glow

// Glow dilation pre-pass: expand thin bright lines before blur.
// Scans 3 concentric rings (8 directions each) + center = 25 samples,
// replacing each pixel with the neighborhood maximum luminance.
// Applied as a layerEffect BEFORE blur so thin lines survive the blur pass.
[[ stitchable ]]
half4 glowDilateEffect(float2 position, SwiftUI::Layer layer, float radius) {
    if (radius < 0.5) return layer.sample(position);

    half4 center = layer.sample(position);
    float maxLum = float(center.r);

    for (int ring = 1; ring <= 3; ring++) {
        float r = radius * float(ring) / 3.0;
        float d = r * 0.707;
        maxLum = max(maxLum, float(layer.sample(position + float2( r,  0)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2(-r,  0)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2( 0,  r)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2( 0, -r)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2( d,  d)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2(-d,  d)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2( d, -d)).r));
        maxLum = max(maxLum, float(layer.sample(position + float2(-d, -d)).r));
    }

    return half4(half(maxLum), half(maxLum), half(maxLum), center.a);
}

// Max-pool dilation: scan 3 concentric rings (8 directions) + center = 25 samples.
static float maxPoolSample(SwiftUI::Layer layer, float2 center, float radius) {
    float maxLum = float(layer.sample(center).r);
    for (int ring = 1; ring <= 3; ring++) {
        float r = radius * float(ring) / 3.0;
        float d = r * 0.707;
        maxLum = max(maxLum, float(layer.sample(center + float2( r,  0)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2(-r,  0)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2( 0,  r)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2( 0, -r)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2( d,  d)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2(-d,  d)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2( d, -d)).r));
        maxLum = max(maxLum, float(layer.sample(center + float2(-d, -d)).r));
    }
    return maxLum;
}

[[ stitchable ]]
half4 posterizePixelateEffect(
    float2 position, SwiftUI::Layer layer,
    float pixelSize, float gridThickness,
    float posterizeLevels,
    float presetMode,
    float paletteCount,
    // 8 palette stops x 3 RGB channels = 24 floats
    float p0r, float p0g, float p0b,
    float p1r, float p1g, float p1b,
    float p2r, float p2g, float p2b,
    float p3r, float p3g, float p3b,
    float p4r, float p4g, float p4b,
    float p5r, float p5g, float p5b,
    float p6r, float p6g, float p6b,
    float p7r, float p7g, float p7b
) {
    int preset = int(presetMode);

    float lum;
    float alpha;
    float gridDarken = 0.0;
    float levels = posterizeLevels;
    bool smoothPalette = false;

    // Per-channel luminance for CRT RGB separation
    float lumR = 0.0, lumG = 0.0, lumB = 0.0;
    bool useSeparateRGB = false;

    switch (preset) {

    case 1: {
        // ── Clean Pixel ──────────────────────────────────────
        // Same square cell + max-pool, no grid lines, forced 4-level posterize
        levels = 4.0;
        if (pixelSize > 1.0) {
            float2 cell = floor(position / pixelSize);
            float2 cellCenter = (cell + 0.5) * pixelSize;
            float radius = pixelSize * 0.5;
            lum = maxPoolSample(layer, cellCenter, radius);
            alpha = float(layer.sample(cellCenter).a);
        } else {
            half4 src = layer.sample(position);
            lum = float(src.r);
            alpha = float(src.a);
        }
        break;
    }

    case 2: {
        // ── Honeycomb ────────────────────────────────────────
        // Hex grid cells with thin hex borders
        if (pixelSize > 1.0) {
            float cellSize = pixelSize * 0.68;
            float3 hex = hexGrid(position, cellSize);
            float2 hexCenter = hex.xy;
            float edgeDist = hex.z;

            float radius = pixelSize * 0.5;
            lum = maxPoolSample(layer, hexCenter, radius);
            alpha = float(layer.sample(hexCenter).a);

            // Hex border — same visual weight as the square grid lines
            float borderWidth = gridThickness;
            gridDarken = 1.0 - smoothstep(0.0, borderWidth * 0.5, edgeDist);
        } else {
            half4 src = layer.sample(position);
            lum = float(src.r);
            alpha = float(src.a);
        }
        break;
    }

    case 3: {
        // ── Halftone ─────────────────────────────────────────
        // Circular dots sized by brightness — comic book / print look
        if (pixelSize > 1.0) {
            float2 cell = floor(position / pixelSize);
            float2 cellCenter = (cell + 0.5) * pixelSize;
            float radius = pixelSize * 0.5;
            lum = maxPoolSample(layer, cellCenter, radius);
            alpha = float(layer.sample(cellCenter).a);

            // Dot mask: distance from pixel to cell center
            float dist = length(position - cellCenter);
            float cellRadius = pixelSize * 0.5;
            float dotRadius = lum * cellRadius * 0.95;
            // Pixels outside the dot are fully darkened
            gridDarken = smoothstep(dotRadius - 0.5, dotRadius + 0.5, dist);
        } else {
            half4 src = layer.sample(position);
            lum = float(src.r);
            alpha = float(src.a);
        }
        break;
    }

    case 4: {
        // ── CRT ──────────────────────────────────────────────
        // Horizontal scanlines + RGB sub-pixel channel separation
        useSeparateRGB = true;
        if (pixelSize > 1.0) {
            float2 cell = floor(position / pixelSize);
            float2 cellCenter = (cell + 0.5) * pixelSize;
            float radius = pixelSize * 0.5;

            // RGB channel separation — offset R left, B right
            float separation = 1.5;
            lumR = maxPoolSample(layer, cellCenter + float2(-separation, 0), radius);
            lumG = maxPoolSample(layer, cellCenter, radius);
            lumB = maxPoolSample(layer, cellCenter + float2( separation, 0), radius);
            lum = lumG; // use green for palette mapping
            alpha = float(layer.sample(cellCenter).a);
        } else {
            float separation = 1.5;
            lumR = float(layer.sample(position + float2(-separation, 0)).r);
            lumG = float(layer.sample(position).r);
            lumB = float(layer.sample(position + float2( separation, 0)).r);
            lum = lumG;
            alpha = float(layer.sample(position).a);
        }

        // Scanline darkening — horizontal bands
        float scanlineHeight = max(pixelSize, 3.0);
        float scanline = sin(position.y * M_PI_F / scanlineHeight);
        gridDarken = (1.0 - abs(scanline)) * 0.3;
        break;
    }

    case 5: {
        // ── Neon ─────────────────────────────────────────────
        // Smooth palette mapping + additive bloom glow, no pixelation
        smoothPalette = true;
        lum = float(layer.sample(position).r);
        alpha = float(layer.sample(position).a);

        // Compute blurred version: 8 surrounding samples for bloom
        float bloomRadius = max(pixelSize, 4.0) * 2.0;
        float blurredLum = 0.0;
        for (int i = 0; i < 8; i++) {
            float angle = float(i) * M_PI_F * 0.25;
            float2 offset = float2(cos(angle), sin(angle)) * bloomRadius;
            blurredLum += float(layer.sample(position + offset).r);
        }
        blurredLum /= 8.0;

        // Additive bloom: glow = difference between blur and sharp
        float glow = max(blurredLum - lum, 0.0);
        lum = lum + glow * 0.6;
        lum = clamp(lum, 0.0, 1.0);
        break;
    }

    default: {
        // ── Pixel Grid (case 0 / fallback) ───────────────────
        // Square cells + grid lines + max-pool (original behavior)
        if (pixelSize > 1.0) {
            float2 cell = floor(position / pixelSize);
            float2 cellCenter = (cell + 0.5) * pixelSize;

            // Grid lines
            float2 cellPos = fract(position / pixelSize);
            float lineThick = gridThickness / pixelSize;
            gridDarken = max(step(cellPos.x, lineThick), step(cellPos.y, lineThick));

            // Max-pool dilation
            float radius = pixelSize * 0.5;
            lum = maxPoolSample(layer, cellCenter, radius);
            alpha = float(layer.sample(cellCenter).a);
        } else {
            half4 src = layer.sample(position);
            lum = float(src.r);
            alpha = float(src.a);
        }
        break;
    }

    } // end switch

    // Build palette array from individual floats
    int count = int(paletteCount);
    count = clamp(count, 2, 8);
    float3 palette[8] = {
        float3(p0r, p0g, p0b),
        float3(p1r, p1g, p1b),
        float3(p2r, p2g, p2b),
        float3(p3r, p3g, p3b),
        float3(p4r, p4g, p4b),
        float3(p5r, p5g, p5b),
        float3(p6r, p6g, p6b),
        float3(p7r, p7g, p7b),
    };

    // Map luminance through palette
    float3 color;
    if (useSeparateRGB) {
        // CRT: map each channel independently then recombine
        float3 colorR = (levels >= 2.0 && !smoothPalette)
            ? gradientMapPosterize(lumR, palette, count, levels)
            : gradientMapSmooth(lumR, palette, count);
        float3 colorG = (levels >= 2.0 && !smoothPalette)
            ? gradientMapPosterize(lumG, palette, count, levels)
            : gradientMapSmooth(lumG, palette, count);
        float3 colorB = (levels >= 2.0 && !smoothPalette)
            ? gradientMapPosterize(lumB, palette, count, levels)
            : gradientMapSmooth(lumB, palette, count);
        color = float3(colorR.r, colorG.g, colorB.b);
    } else if (smoothPalette || levels < 2.0) {
        color = gradientMapSmooth(lum, palette, count);
    } else {
        color = gradientMapPosterize(lum, palette, count, levels);
    }

    // Grid/mask darkening
    color *= (1.0 - gridDarken);
    alpha *= (1.0 - gridDarken);

    return half4(half3(color), half(alpha));
}
