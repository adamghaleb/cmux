#include <metal_stdlib>
#include "WorkingStatePipeline.h"
using namespace metal;

// Spirit Molecule: the DMT molecule itself - hexagonal ring structures with electron clouds

[[ stitchable ]]
half4 spiritMoleculeEffect(
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

    // Molecular breathing
    float breathe = 1.0 + 0.03 * sin(t * 0.6);
    p *= breathe;

    // Indole ring system: fused benzene + pyrrole (the core of DMT)
    // Benzene hexagonal ring (6 atoms)
    float bondWidth = 0.008;
    float atomRadius = 0.025;
    float ringScale = 0.18;

    float2 benzeneCenter = float2(-0.08, 0.0);
    float2 benzeneAtoms[6];
    for (int i = 0; i < 6; i++) {
        float a = float(i) * M_PI_F / 3.0 + M_PI_F / 6.0;
        benzeneAtoms[i] = benzeneCenter + float2(cos(a), sin(a)) * ringScale;
    }

    // Pyrrole ring (5 atoms, fused with benzene sharing 2 atoms)
    float2 pyrroleCenter = float2(0.12, 0.0);
    float pyrroleScale = 0.16;
    float2 pyrroleAtoms[5];
    pyrroleAtoms[0] = benzeneAtoms[0]; // shared
    pyrroleAtoms[1] = benzeneAtoms[5]; // shared
    for (int i = 2; i < 5; i++) {
        float a = float(i - 2) * M_PI_F * 2.0 / 5.0 - 0.3;
        pyrroleAtoms[i] = pyrroleCenter + float2(cos(a), sin(a)) * pyrroleScale;
    }

    // Dimethyl amine tail: N-CH3 groups extending from indole
    float2 tailN = float2(0.3, 0.05);
    float2 tailCH3a = float2(0.42, 0.15);
    float2 tailCH3b = float2(0.42, -0.08);
    float2 tailBridge = float2(0.22, 0.08);

    // Draw bonds as glowing lines
    // Benzene bonds
    for (int i = 0; i < 6; i++) {
        float2 ba = benzeneAtoms[(i + 1) % 6] - benzeneAtoms[i];
        float blen = length(ba);
        float2 bdir = ba / blen;
        float bt = clamp(dot(p - benzeneAtoms[i], bdir), 0.0, blen);
        float bd = length(p - (benzeneAtoms[i] + bdir * bt));
        float bel = sin(bt / blen * 12.0 - t * 3.0) * 0.3 + 0.7;
        lum += smoothstep(bondWidth * 2.0, 0.0, bd) * bel * 0.25;
    }

    // Pyrrole bonds (non-shared edges) + Tail bonds — packed into arrays
    float2 bondA[8] = { pyrroleAtoms[1], pyrroleAtoms[2], pyrroleAtoms[3], pyrroleAtoms[4],
                        pyrroleAtoms[3], tailBridge, tailN, tailN };
    float2 bondB[8] = { pyrroleAtoms[2], pyrroleAtoms[3], pyrroleAtoms[4], pyrroleAtoms[0],
                        tailBridge, tailN, tailCH3a, tailCH3b };
    for (int i = 0; i < 8; i++) {
        float2 ba = bondB[i] - bondA[i];
        float blen = length(ba);
        float2 bdir = ba / blen;
        float bt = clamp(dot(p - bondA[i], bdir), 0.0, blen);
        float bd = length(p - (bondA[i] + bdir * bt));
        float bel = sin(bt / blen * 12.0 - t * 3.0) * 0.3 + 0.7;
        lum += smoothstep(bondWidth * 2.0, 0.0, bd) * bel * 0.25;
    }

    // Draw atoms as glowing nodes
    for (int i = 0; i < 6; i++) {
        float d = length(p - benzeneAtoms[i]);
        float pulse = sin(t * 1.2 + float(i) * 1.047) * 0.2 + 0.8;
        lum += smoothstep(atomRadius, 0.0, d) * 0.3 * pulse;
    }
    for (int i = 2; i < 5; i++) {
        float d = length(p - pyrroleAtoms[i]);
        float pulse = sin(t * 1.0 + float(i) * 1.256) * 0.2 + 0.8;
        lum += smoothstep(atomRadius, 0.0, d) * 0.3 * pulse;
    }
    // Nitrogen atom (brighter)
    float dN = length(p - tailN);
    lum += smoothstep(atomRadius * 1.3, 0.0, dN) * 0.45;
    lum += smoothstep(atomRadius, 0.0, length(p - tailCH3a)) * 0.2;
    lum += smoothstep(atomRadius, 0.0, length(p - tailCH3b)) * 0.2;
    lum += smoothstep(atomRadius, 0.0, length(p - tailBridge)) * 0.2;

    // Delocalized pi electron cloud over the aromatic rings
    float piCloud = 0.0;
    float dBenz = length(p - benzeneCenter);
    float dPyr = length(p - pyrroleCenter);
    piCloud += smoothstep(ringScale * 1.3, ringScale * 0.3, dBenz) * 0.15;
    piCloud += smoothstep(pyrroleScale * 1.3, pyrroleScale * 0.3, dPyr) * 0.12;
    // Oscillating electron density
    float piOsc = sin(atan2(p.y - benzeneCenter.y, p.x - benzeneCenter.x) * 6.0 + t * 2.0);
    piCloud *= 0.7 + 0.3 * piOsc;
    lum += piCloud;

    // Quantum orbital cloud: probability density around the molecule
    float orbital = 0.0;
    float2 moleculeCenter = float2(0.1, 0.0);
    float dMol = length(p - moleculeCenter);
    float molAngle = atan2(p.y - moleculeCenter.y, p.x - moleculeCenter.x);

    // p-orbital lobes
    for (int i = 0; i < 3; i++) {
        float lobeAngle = float(i) * M_PI_F / 3.0 + t * 0.15;
        float angDiff = molAngle - lobeAngle;
        float lobe = pow(max(0.0, cos(angDiff)), 4.0);
        lobe *= exp(-dMol * 3.0) * smoothstep(0.0, 0.2, dMol);
        orbital += lobe * 0.08;
    }
    lum += orbital;

    // Background: faint molecular field
    float field = simplex2d(p * 4.0 + float2(t * 0.2, 0.0)) * 0.5 + 0.5;
    field *= exp(-dMol * 1.5) * 0.06;
    lum += field;

    lum *= smoothstep(1.6, 0.2, s.dist);
    lum = clamp(lum, 0.0, 1.0);
    return pipelineFinalize(lum, intensity, float3(themeR, themeG, themeB), posterizeLevels, s.gridDarken, hueSpread, complementMix, contrast, brightness);
}
