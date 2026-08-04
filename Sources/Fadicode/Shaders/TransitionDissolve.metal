#include <metal_stdlib>
using namespace metal;

// ============================================================
// Cinematic luminance dissolve.
//
// Two cascading effects on raw grayscale layers BEFORE posterization:
//
// 1. New shader (lumaRevealEffect): ease-in envelope + bright areas
//    appear first, cascading down to dark.
//
// 2. Old shader (lumaDissolveOut): dark areas leave first, bright
//    areas linger longest — each pixel has its own fade-out window
//    based on luminance. White is the last to go.
//
// SwiftUI colorEffects use premultiplied alpha — multiply ALL
// four channels to properly fade.
// ============================================================

// --- New shader: luma-biased reveal with global ease-in ---
[[ stitchable ]]
half4 lumaRevealEffect(
    float2 position, half4 currentColor,
    float progress
) {
    if (progress >= 1.0) return currentColor;
    if (progress <= 0.0) return half4(0.0h);

    half p = half(progress);
    half lum = currentColor.r;

    // Global ease-in: prevents bright areas from popping instantly.
    half globalAlpha = smoothstep(0.0h, 0.35h, p);

    // Luma-biased progress: bright pixels are further along.
    half lumShift = (lum - 0.5h) * 0.5h;
    half localP = saturate(p + lumShift);

    // Per-pixel smooth fade (hermite).
    half t = localP;
    half reveal = t * t * (3.0h - 2.0h * t);

    // Combine: envelope × cascade.
    reveal *= globalAlpha;

    return currentColor * reveal;
}

// --- Old shader: cascading dissolve, white lingers longest ---
[[ stitchable ]]
half4 lumaDissolveOut(
    float2 position, half4 currentColor,
    float progress
) {
    if (progress <= 0.0) return currentColor;
    if (progress >= 1.0) return half4(0.0h);

    half p = half(progress);
    half lum = currentColor.r;

    // Each pixel has its own fade-out window based on luminance.
    // Dark pixels (lum=0): window starts at 30%, ends at 80%.
    // Bright pixels (lum=1): window starts at 50%, ends at 100%.
    // → White is the last to go.
    half windowWidth = 0.5h;
    half fadeStart = mix(0.3h, 0.5h, lum);

    // Normalize progress within this pixel's window.
    half t = saturate((p - fadeStart) / windowWidth);

    // Smooth hermite dissolve per pixel.
    half fade = t * t * (3.0h - 2.0h * t);
    half keep = 1.0h - fade;

    return currentColor * keep;
}
