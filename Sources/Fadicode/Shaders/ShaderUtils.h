#ifndef ShaderUtils_h
#define ShaderUtils_h

#include <metal_stdlib>
using namespace metal;

// ============================================================
// Hash functions
// ============================================================

static inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ============================================================
// Simplex 2D noise
// ============================================================

static inline float simplex2d(float2 p) {
    const float K1 = 0.366025404;
    const float K2 = 0.211324865;
    float2 i = floor(p + (p.x + p.y) * K1);
    float2 a = p - i + (i.x + i.y) * K2;
    float2 o = (a.x > a.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 b = a - o + K2;
    float2 c = a - 1.0 + 2.0 * K2;
    float3 h = max(0.5 - float3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
    h = h * h * h * h;
    float2 ga = hash22(i) * 2.0 - 1.0;
    float2 gb = hash22(i + o) * 2.0 - 1.0;
    float2 gc = hash22(i + 1.0) * 2.0 - 1.0;
    float3 n = h * float3(dot(ga, a), dot(gb, b), dot(gc, c));
    return dot(n, float3(70.0));
}

// ============================================================
// Fractal Brownian Motion
// ============================================================

static inline float fbm(float2 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    float2 shift = float2(100.0);
    float2 warp = float2(
        simplex2d(p + float2(0.0, time * 0.3)),
        simplex2d(p + float2(5.2, time * 0.36))
    );
    p += warp * 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * simplex2d(p);
        p = p * 2.0 + shift;
        amplitude *= 0.5;
    }
    return value;
}

// ============================================================
// HSV <-> RGB
// ============================================================

static inline float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

static inline float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// ============================================================
// Posterize: analogous gradient ramp around theme color
// Shadows → cooler neighbor, Mids → theme, Highlights → warmer neighbor
// Complement bleeds into highlights only
// ============================================================

static inline float3 posterize(float lum, float3 themeRGB, float levels,
                                float hueSpread = 0.10, float complementMix = 0.0) {
    float3 themeHSV = rgb2hsv(themeRGB);
    float baseHue = themeHSV.x;
    float baseSat = max(themeHSV.y, 0.6);

    // Quantize brightness into bands
    float q = floor(lum * levels) / levels;

    // Band thresholds for white transition
    float topBand = (levels - 1.0) / levels;
    float bridgeBand = (levels - 2.0) / levels;

    // Analogous hue ramp: ±hueSpread on the color wheel
    // q=0 (shadow) → cooler, q=0.5 (mid) → theme, q=1 (highlight) → warmer
    float hueT = q * 2.0 - 1.0; // remap 0..1 → -1..+1
    float hueOffset = hueT * hueSpread;
    float hue = fract(baseHue + hueOffset);

    // Saturation: richest at mid-tones, desaturate in deep shadows and bright highlights
    float satCurve = 1.0 - (hueT * hueT) * 0.5;
    float sat = baseSat * satCurve;
    sat = max(sat, baseSat * 0.3);
    sat = mix(sat * 1.15, sat, smoothstep(0.0, 0.4, q));

    // Value: gradient ramp from near-black to bright
    float val = mix(0.06, 1.2, q);
    val = clamp(val, 0.0, 1.0);

    // Top band → pure white, bridge band → light desaturated stepping stone
    if (q >= topBand) {
        sat = 0.0;
        val = 1.0;
    } else if (q >= bridgeBand) {
        sat *= 0.3;
        val = mix(val, 1.0, 0.65);
    }

    float3 analogousColor = hsv2rgb(float3(hue, sat, val));

    // Complementary accent: opposite hue, only in highlights
    if (complementMix > 0.001) {
        float compHue = fract(baseHue + 0.5);
        float compSat = baseSat * 0.85;
        float3 compColor = hsv2rgb(float3(compHue, compSat, val));

        // Blend factor: rises steeply only in bright bands
        float compBlend = smoothstep(0.55, 1.0, q) * complementMix;
        analogousColor = mix(analogousColor, compColor, compBlend);
    }

    return analogousColor;
}

// ============================================================
// Gradient Map: map luminance to a multi-stop color palette
// palette[] contains up to 8 RGB colors evenly or custom-spaced
// ============================================================

/// Smooth interpolation: lerp between adjacent palette stops based on luminance
static inline float3 gradientMapSmooth(float lum, float3 palette[8], int count) {
    if (count <= 1) return palette[0];
    float t = clamp(lum, 0.0, 1.0) * float(count - 1);
    int idx = int(t);
    float frac = t - float(idx);
    idx = min(idx, count - 2);
    return mix(palette[idx], palette[idx + 1], frac);
}

/// Posterized gradient map: quantize luminance into bands, then map to palette
static inline float3 gradientMapPosterize(float lum, float3 palette[8], int count, float levels) {
    if (levels < 2.0) {
        // No posterization — smooth gradient map
        return gradientMapSmooth(lum, palette, count);
    }
    // Quantize luminance into discrete bands
    float q = floor(lum * levels) / levels;
    return gradientMapSmooth(q, palette, count);
}

// ============================================================
// Hex Grid: axial coordinate snap + edge distance
// Returns float3(center.x, center.y, edgeDist)
// ============================================================

static inline float3 hexGrid(float2 position, float cellSize) {
    // Convert to axial hex coordinates
    float2 q = float2(position.x * 2.0 / 3.0, (-position.x / 3.0 + sqrt(3.0) / 3.0 * position.y));
    q /= cellSize;
    // Cube coordinates
    float3 cube = float3(q.x, q.y, -q.x - q.y);
    float3 rounded = round(cube);
    float3 diff = abs(rounded - cube);
    if (diff.x > diff.y && diff.x > diff.z)
        rounded.x = -rounded.y - rounded.z;
    else if (diff.y > diff.z)
        rounded.y = -rounded.x - rounded.z;
    else
        rounded.z = -rounded.x - rounded.y;
    // Hex center in pixel coords
    float2 center = float2(rounded.x * 1.5, sqrt(3.0) * (rounded.y + rounded.x * 0.5)) * cellSize;

    // Hexagonal edge distance — must match the flat-top layout above.
    // Flat-top hex norm: max(|dy|, |dx|*√3/2 + |dy|*0.5)
    // This gives straight hex edges aligned with the tiling.
    float2 d = abs(position - center);
    float inradius = cellSize * 0.866025; // √3/2 — center to flat edge
    float hexNorm = max(d.y, d.x * 0.866025 + d.y * 0.5);
    float edgeDist = inradius - hexNorm;

    return float3(center, edgeDist);
}

#endif
