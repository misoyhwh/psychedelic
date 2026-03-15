#include <metal_stdlib>
using namespace metal;

struct PsychedelicParams {
    float time;
    float speed;
    float intensity;
    int styleIndex;
    int width;
    int height;
};

float3 hsvToRgb(float h, float s, float v) {
    float c = v * s;
    float x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0));
    float m = v - c;
    float3 rgb;
    int sector = int(h * 6.0) % 6;
    switch (sector) {
        case 0: rgb = float3(c, x, 0); break;
        case 1: rgb = float3(x, c, 0); break;
        case 2: rgb = float3(0, c, x); break;
        case 3: rgb = float3(0, x, c); break;
        case 4: rgb = float3(x, 0, c); break;
        default: rgb = float3(c, 0, x); break;
    }
    return rgb + m;
}

float pseudoNoise(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float smoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = pseudoNoise(i);
    float b = pseudoNoise(i + float2(1.0, 0.0));
    float c = pseudoNoise(i + float2(0.0, 1.0));
    float d = pseudoNoise(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * smoothNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

float4 psychedelicPattern(float2 uv, float t, float intensity) {
    float2 p = uv * 4.0 * intensity;

    float n1 = fbm(p + float2(t * 0.3, t * 0.2));
    float n2 = fbm(p * 1.5 + float2(-t * 0.2, t * 0.4) + n1 * 2.0);
    float n3 = fbm(p * 0.8 + float2(t * 0.1, -t * 0.3) + n2 * 2.0);

    float wave1 = sin(p.x * 3.0 + n1 * 6.0 + t) * 0.5 + 0.5;
    float wave2 = sin(p.y * 4.0 + n2 * 5.0 - t * 0.7) * 0.5 + 0.5;
    float wave3 = cos((p.x + p.y) * 2.5 + n3 * 4.0 + t * 1.3) * 0.5 + 0.5;

    float r = sin(wave1 * M_PI_F * 2.0 + n1 * 4.0) * 0.5 + 0.5;
    float g = sin(wave2 * M_PI_F * 2.0 + n2 * 4.0 + M_PI_F * 2.0 / 3.0) * 0.5 + 0.5;
    float b = sin(wave3 * M_PI_F * 2.0 + n3 * 4.0 + M_PI_F * 4.0 / 3.0) * 0.5 + 0.5;

    // Extra color saturation boost
    float3 color = float3(r, g, b);
    float gray = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(float3(gray), color, 1.8); // Boost saturation
    color = clamp(color, 0.0, 1.0);

    return float4(color, 0.8);
}

float4 fractalPattern(float2 uv, float t, float intensity) {
    float2 z = (uv - 0.5) * 3.0;
    float2 c = float2(sin(t * 0.3) * 0.4, cos(t * 0.2) * 0.4);

    float iter = 0.0;
    float maxIter = 30.0;
    while (iter < maxIter && dot(z, z) < 4.0) {
        float tmp = z.x * z.x - z.y * z.y + c.x;
        z.y = 2.0 * z.x * z.y + c.y;
        z.x = tmp;
        iter += 1.0;
    }

    float ratio = iter / maxIter;
    float smooth_val = ratio + 1.0 - log2(max(1.0, log2(length(z))));
    smooth_val = fract(smooth_val * 0.5 + t * 0.1);

    float3 color = hsvToRgb(smooth_val, 1.0, ratio < 1.0 ? 1.0 : 0.0);
    color *= intensity;
    return float4(clamp(color, 0.0, 1.0), 0.8);
}

// Hatsune Miku "39" palette — weighted 10 slots
// #373b3e:10% #fffeec:10% #66ddcc:30% #86cecb:10% #137a7f:10% #e12885:30%
constant float3 miku39_palette[10] = {
    float3(0.216, 0.231, 0.243),  // #373b3e dark gray      (1/10 = 10%)
    float3(1.000, 0.996, 0.925),  // #fffeec cream           (1/10 = 10%)
    float3(0.400, 0.867, 0.800),  // #66ddcc bright teal     (1/3)
    float3(0.400, 0.867, 0.800),  // #66ddcc bright teal     (2/3)
    float3(0.400, 0.867, 0.800),  // #66ddcc bright teal     (3/3)
    float3(0.525, 0.808, 0.796),  // #86cecb miku teal       (1/10 = 10%)
    float3(0.075, 0.478, 0.498),  // #137a7f deep teal       (1/10 = 10%)
    float3(0.882, 0.157, 0.522),  // #e12885 miku pink       (1/3)
    float3(0.882, 0.157, 0.522),  // #e12885 miku pink       (2/3)
    float3(0.882, 0.157, 0.522),  // #e12885 miku pink       (3/3)
};

float3 sampleMiku39Palette(float idx) {
    float fi = fract(idx) * 10.0;
    int i0 = int(fi) % 10;
    int i1 = (i0 + 1) % 10;
    float frac_part = fract(fi);
    return mix(miku39_palette[i0], miku39_palette[i1], frac_part);
}

float4 miku39Pattern(float2 uv, float t, float intensity) {
    float2 p = uv * 4.0 * intensity;

    // Same fBM noise structure as psychedelicPattern
    float n1 = fbm(p + float2(t * 0.3, t * 0.2));
    float n2 = fbm(p * 1.5 + float2(-t * 0.2, t * 0.4) + n1 * 2.0);
    float n3 = fbm(p * 0.8 + float2(t * 0.1, -t * 0.3) + n2 * 2.0);

    float wave1 = sin(p.x * 3.0 + n1 * 6.0 + t) * 0.5 + 0.5;
    float wave2 = sin(p.y * 4.0 + n2 * 5.0 - t * 0.7) * 0.5 + 0.5;
    float wave3 = cos((p.x + p.y) * 2.5 + n3 * 4.0 + t * 1.3) * 0.5 + 0.5;

    // Use wave values to sample from miku palette instead of RGB sine waves
    float idx1 = fract(wave1 + n1 * 0.5);
    float idx2 = fract(wave2 + n2 * 0.5 + 0.33);
    float idx3 = fract(wave3 + n3 * 0.5 + 0.66);

    float3 c1 = sampleMiku39Palette(idx1);
    float3 c2 = sampleMiku39Palette(idx2);
    float3 c3 = sampleMiku39Palette(idx3);

    // Blend the three palette lookups with psychedelic weighting
    float3 color = c1 * wave1 + c2 * wave2 + c3 * wave3;
    color /= (wave1 + wave2 + wave3 + 0.001);

    // Saturation boost
    float gray = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(float3(gray), color, 1.6);
    color = clamp(color, 0.0, 1.0);

    return float4(color, 0.8);
}

float4 rainbowPattern(float2 uv, float t, float intensity) {
    float2 center = uv - 0.5;
    float dist = length(center);
    float angle = atan2(center.y, center.x);

    float n = fbm(uv * 3.0 * intensity + float2(t * 0.2));

    float hue = fract(angle / (M_PI_F * 2.0) + dist * 3.0 * intensity + n * 0.5 - t * 0.3);
    float3 color = hsvToRgb(hue, 1.0, 1.0);

    // Add swirl distortion
    float swirl = sin(dist * 10.0 * intensity - t * 2.0 + n * 5.0) * 0.5 + 0.5;
    color *= 0.7 + swirl * 0.3;

    return float4(color, 0.8);
}

// ============================================================
// Aurora Borealis — flowing curtains of light
// ============================================================
float4 auroraPattern(float2 uv, float t, float intensity) {
    float2 p = uv * 2.0 * intensity;

    // Vertical curtain waves
    float curtain1 = sin(p.x * 3.0 + t * 0.5 + fbm(float2(p.x * 2.0, t * 0.3)) * 3.0);
    float curtain2 = sin(p.x * 5.0 - t * 0.3 + fbm(float2(p.x * 1.5, t * 0.2 + 5.0)) * 2.0);
    float curtain3 = sin(p.x * 7.0 + t * 0.7 + fbm(float2(p.x * 3.0, t * 0.15 + 10.0)) * 1.5);

    // Vertical fade — aurora is brighter toward the top
    float vertFade = smoothstep(0.0, 0.8, uv.y) * smoothstep(1.0, 0.6, uv.y);

    // Flowing noise for organic motion
    float n1 = fbm(p + float2(t * 0.2, t * 0.1));
    float n2 = fbm(p * 1.3 + float2(-t * 0.15, t * 0.25) + n1);

    // Layer intensities
    float layer1 = pow(max(0.0, 0.5 + curtain1 * 0.5), 3.0) * vertFade;
    float layer2 = pow(max(0.0, 0.5 + curtain2 * 0.5), 4.0) * vertFade;
    float layer3 = pow(max(0.0, 0.5 + curtain3 * 0.5), 5.0) * vertFade;

    // Aurora colors: green core, purple/blue edges, pink highlights
    float3 green  = float3(0.1, 0.9, 0.3);
    float3 cyan   = float3(0.1, 0.7, 0.8);
    float3 purple = float3(0.5, 0.1, 0.8);
    float3 pink   = float3(0.9, 0.2, 0.5);

    float3 color = green * layer1 * (0.8 + n1 * 0.4)
                 + cyan * layer2 * (0.6 + n2 * 0.5)
                 + purple * layer3 * 0.7
                 + pink * layer1 * layer2 * 0.5;

    // Shimmer
    float shimmer = sin(p.x * 20.0 + p.y * 10.0 + t * 4.0) * 0.5 + 0.5;
    color += float3(0.05, 0.15, 0.1) * shimmer * vertFade * n1;

    // Dark background with subtle blue
    color += float3(0.01, 0.02, 0.05) * (1.0 - vertFade * 0.5);

    return float4(clamp(color, 0.0, 1.0), 0.85);
}

// ============================================================
// Voronoi Cells — organic morphing cell structure
// ============================================================
float2 voronoiHash(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float4 voronoiPattern(float2 uv, float t, float intensity) {
    float2 p = uv * 6.0 * intensity;

    // Warp space with noise for organic feel
    float n = fbm(uv * 3.0 + float2(t * 0.1));
    p += float2(n * 1.5, fbm(uv * 2.5 + float2(0, t * 0.12)) * 1.5);

    float2 ip = floor(p);
    float2 fp = fract(p);

    float minDist1 = 10.0;
    float minDist2 = 10.0;
    float2 nearestPoint = float2(0.0);
    float cellId = 0.0;

    // Search 3x3 neighborhood
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 offset = voronoiHash(ip + neighbor);
            // Animate cell centers
            offset = 0.5 + 0.5 * sin(t * 0.5 + offset * 6.2831);
            float2 diff = neighbor + offset - fp;
            float dist = length(diff);

            if (dist < minDist1) {
                minDist2 = minDist1;
                minDist1 = dist;
                nearestPoint = ip + neighbor;
                cellId = pseudoNoise(ip + neighbor);
            } else if (dist < minDist2) {
                minDist2 = dist;
            }
        }
    }

    // Edge detection
    float edge = minDist2 - minDist1;
    float edgeLine = 1.0 - smoothstep(0.0, 0.08, edge);

    // Cell color based on cell ID — cycle through hues
    float hue = fract(cellId + t * 0.05);
    float sat = 0.7 + 0.3 * sin(cellId * 20.0 + t);
    float3 cellColor = hsvToRgb(hue, sat, 0.7 + 0.3 * cellId);

    // Interior glow — brighter at center
    float glow = exp(-minDist1 * 3.0);
    cellColor *= 0.5 + glow * 0.8;

    // Bright edges
    float3 edgeColor = hsvToRgb(fract(hue + 0.5), 1.0, 1.0);
    float3 color = mix(cellColor, edgeColor, edgeLine * 0.8);

    // Pulse
    float pulse = sin(t * 2.0 + cellId * 10.0) * 0.15 + 0.85;
    color *= pulse;

    return float4(clamp(color, 0.0, 1.0), 0.8);
}

// ============================================================
// Interference — concentric wave interference from multiple sources
// ============================================================
float4 interferencePattern(float2 uv, float t, float intensity) {
    // Multiple wave sources that drift slowly
    float2 src1 = float2(0.3 + sin(t * 0.2) * 0.2, 0.3 + cos(t * 0.15) * 0.2);
    float2 src2 = float2(0.7 + cos(t * 0.25) * 0.2, 0.6 + sin(t * 0.18) * 0.2);
    float2 src3 = float2(0.5 + sin(t * 0.3 + 2.0) * 0.25, 0.2 + cos(t * 0.22 + 1.0) * 0.15);
    float2 src4 = float2(0.2 + cos(t * 0.17 + 3.0) * 0.15, 0.8 + sin(t * 0.28 + 2.0) * 0.15);

    float freq = 20.0 * intensity;
    float speed = t * 3.0;

    // Waves from each source
    float d1 = length(uv - src1);
    float d2 = length(uv - src2);
    float d3 = length(uv - src3);
    float d4 = length(uv - src4);

    float w1 = sin(d1 * freq - speed) / (1.0 + d1 * 4.0);
    float w2 = sin(d2 * freq - speed * 1.1 + 1.0) / (1.0 + d2 * 4.0);
    float w3 = sin(d3 * freq * 0.8 - speed * 0.9 + 2.0) / (1.0 + d3 * 5.0);
    float w4 = sin(d4 * freq * 1.2 - speed * 1.2 + 3.0) / (1.0 + d4 * 3.0);

    float combined = (w1 + w2 + w3 + w4);

    // Map interference to color
    float positive = max(0.0, combined);
    float negative = max(0.0, -combined);

    // Constructive interference = bright, destructive = dark
    float brightness = combined * 0.5 + 0.5;
    float hue = fract(brightness * 0.6 + t * 0.03 + (d1 + d2) * 0.3);

    float3 color = hsvToRgb(hue, 0.8, brightness * brightness);

    // Add bright spots at constructive interference peaks
    float peak = pow(max(0.0, combined * 0.5 + 0.3), 4.0);
    color += float3(0.3, 0.5, 1.0) * peak;

    // Subtle glow near sources
    float srcGlow = exp(-d1 * 6.0) + exp(-d2 * 6.0) + exp(-d3 * 6.0) + exp(-d4 * 6.0);
    color += float3(0.1, 0.2, 0.3) * srcGlow * 0.3;

    return float4(clamp(color, 0.0, 1.0), 0.8);
}

// ============================================================
// GLSL-compatible mod (handles negatives like GLSL)
// ============================================================
float glsl_mod(float x, float y) {
    return x - y * floor(x / y);
}

// ============================================================
// Hex Tunnel — raymarched hexagonal tunnel (Renard_VRC)
// ============================================================
float4 hexTunnelPattern(float2 uv, float t, float intensity) {
    float2 FC = float2(uv.x * 256.0, uv.y * 256.0);
    float2 r = float2(256.0, 256.0);
    float4 o = float4(0.0);

    for (float i = 0.0; i < 99.0; i += 1.0) {
        float l = 1.0;
        float d = 0.0;
        float z = 0.0;

        // Accumulate ray
        float3 P = float3((FC.xy - r * 0.5) / r.y, 0.5) * l;
        z = P.z + t * 5.0 * intensity;
        P.z = fract(z) - 0.5;
        float angle = atan2(P.y, P.x);
        P.x = cos(glsl_mod(angle + z * 0.2, M_PI_F / 3.0) - M_PI_F / 6.0) * length(P.xy) - 2.0;
        d = max(abs(length(float2(P.x, P.z)) - 0.2), 0.01);
        l += d;

        // Re-march with accumulated length
        for (float j = 1.0; j < 99.0; j += 1.0) {
            P = float3((FC.xy - r * 0.5) / r.y, 0.5) * l;
            z = P.z + t * 5.0 * intensity;
            P.z = fract(z) - 0.5;
            angle = atan2(P.y, P.x);
            P.x = cos(glsl_mod(angle + z * 0.2, M_PI_F / 3.0) - M_PI_F / 6.0) * length(P.xy) - 2.0;
            d = max(abs(length(float2(P.x, P.z)) - 0.2), 0.01);
            l += d;
            o += exp(-d * 5.0) * 0.01 * (0.9 + 0.7 * float4(cos(z), cos(z + 0.2), cos(z + 0.3), 0.0));
        }
        break; // Single pass with inner loop
    }

    o.w = 0.8;
    return clamp(o, 0.0, 1.0);
}

// ============================================================
// Organic Structure — raymarched organic/coral (XorDev)
// ============================================================
float4 organicPattern(float2 uv, float t, float intensity) {
    float2 FC = float2(uv.x * 256.0, uv.y * 256.0);
    float2 r = float2(256.0, 256.0);
    float4 o = float4(0.0);

    for (float i = 0.0; i < 40.0; i += 1.0) {
        float z = 0.0;
        float d = 0.0;
        float3 p = z * normalize(float3(FC.x * 2.0 - r.x, FC.y * 2.0 - r.y, -r.y));
        p.z -= t * intensity;
        z += d;
        float3 v = cos(p) + cos(float3(p.y, p.z, p.x) * 0.2);
        d = length(max(v, -v / 7.0));
        z += d;

        // Iterate
        for (float j = 1.0; j < 40.0; j += 1.0) {
            p = z * normalize(float3(FC.x * 2.0 - r.x, FC.y * 2.0 - r.y, -r.y));
            p.z -= t * intensity;
            v = cos(p) + cos(float3(p.y, p.z, p.x) * 0.2);
            d = length(max(v, -v / 7.0));
            z += d;
            o += (sin(z + float4(0.0, 1.0, 3.0, 3.0)) + 1.0) / d;
        }
        break;
    }

    o = tanh(o / 1000.0);
    o.w = 0.8;
    return clamp(o, 0.0, 1.0);
}

// ============================================================
// Sparkles — sparkling particle effect (XorDev)
// ============================================================
float4 sparklesPattern(float2 uv, float t, float intensity) {
    float2 FC = float2(uv.x * 256.0, uv.y * 256.0);
    float2 r = float2(256.0, 256.0);
    float4 o = float4(0.0);

    float tScaled = t * intensity;
    for (float i = -fract(tScaled / 0.1); i < 100.0; i += 1.0) {
        float j = round(i + tScaled / 0.1);
        float jj = j * j;
        float4 col = (cos(jj + float4(0.0, 1.0, 2.0, 3.0)) + 1.0);
        float brightness = exp(cos(jj / 0.1) / 0.6);
        float fade = min(1000.0 - i / 0.1 + 9.0, i) / 50000.0;
        float2 center = (FC.xy - r * 0.5) / r.y + 0.05 * cos(jj / float2(4.0, 4.0) + float2(0.0, 5.0)) * sqrt(i);
        float dist = length(center);
        o += col * brightness * fade / max(dist, 0.001);
    }

    o = tanh(o * o);
    o.w = 0.8;
    return clamp(o, 0.0, 1.0);
}

// ============================================================
// Hearts — floating hearts with pink glow
// ============================================================
float4 heartsPattern(float2 uv, float t, float intensity) {
    float2 r = float2(256.0, 256.0);
    float2 FC = float2(uv.x * 256.0, uv.y * 256.0);
    float2 p = (FC.xy * 2.0 - r) / r.x * 3.0;
    p.y = -p.y; // Flip Y so hearts point upward

    float v = 0.1;
    for (float i = 0.0; i < 11.0; i += 1.0) {
        float2 c = sin(float2(i, i * 1.4) + t * 0.5 * intensity);
        float2 q = (p - c) * 0.9;
        q.y -= sqrt(abs(q.x)) * 0.5;
        float d = length(q) - 0.3 + sin(q.x * 5.0 + t) * 0.05;
        v += 0.015 / abs(d);
    }

    return float4(float3(1.0, 0.15, 0.4) * v, 0.8);
}

// ============================================================
// Caustic Fractal — water caustics with palette
// ============================================================
float3 causticPalette(float val, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * val + d));
}

float4 causticPattern(float2 uv, float t, float intensity) {
    float2 p = (uv - 0.5) * 4.0;
    float2 p0 = p;

    float3 finalColor = float3(0.0);
    for (float i = 0.0; i < 4.0; i += 1.0) {
        p = fract(p * 1.5) - 0.5;

        float d = length(p) * exp(-length(p0));
        float3 col = causticPalette(
            length(p0) + i * 0.4 + t * 0.4 * intensity,
            float3(0.5, 0.5, 0.5),
            float3(0.5, 0.5, 0.5),
            float3(1.0, 1.0, 1.0),
            float3(0.263, 0.416, 0.557)
        );

        d = sin(d * 8.0 + t * intensity) / 8.0;
        d = abs(d);
        d = pow(0.01 / d, 1.2);

        finalColor += col * d;
    }

    return float4(clamp(finalColor, 0.0, 1.0), 0.8);
}

// ============================================================
// Video Psychedelic — luminance pattern for video color tinting
// ============================================================
float4 videoPsychedelicPattern(float2 uv, float t, float intensity) {
    float2 p = uv * 4.0 * intensity;

    float n1 = fbm(p + float2(t * 0.3, t * 0.2));
    float n2 = fbm(p * 1.5 + float2(-t * 0.2, t * 0.4) + n1 * 2.0);
    float n3 = fbm(p * 0.8 + float2(t * 0.1, -t * 0.3) + n2 * 2.0);

    float wave1 = sin(p.x * 3.0 + n1 * 6.0 + t) * 0.5 + 0.5;
    float wave2 = sin(p.y * 4.0 + n2 * 5.0 - t * 0.7) * 0.5 + 0.5;
    float wave3 = cos((p.x + p.y) * 2.5 + n3 * 4.0 + t * 1.3) * 0.5 + 0.5;

    float lum = (wave1 + wave2 + wave3) / 3.0;
    lum = pow(lum, 0.7); // Boost contrast slightly
    lum = clamp(lum, 0.0, 1.0);

    return float4(lum, lum, lum, 0.8);
}

// ============================================================
// Video Interference — luminance pattern for video color tinting
// ============================================================
float4 videoInterferencePattern(float2 uv, float t, float intensity) {
    float2 src1 = float2(0.3 + sin(t * 0.2) * 0.2, 0.3 + cos(t * 0.15) * 0.2);
    float2 src2 = float2(0.7 + cos(t * 0.25) * 0.2, 0.6 + sin(t * 0.18) * 0.2);
    float2 src3 = float2(0.5 + sin(t * 0.3 + 2.0) * 0.25, 0.2 + cos(t * 0.22 + 1.0) * 0.15);
    float2 src4 = float2(0.2 + cos(t * 0.17 + 3.0) * 0.15, 0.8 + sin(t * 0.28 + 2.0) * 0.15);

    float freq = 20.0 * intensity;
    float speed = t * 3.0;

    float d1 = length(uv - src1);
    float d2 = length(uv - src2);
    float d3 = length(uv - src3);
    float d4 = length(uv - src4);

    float w1 = sin(d1 * freq - speed) / (1.0 + d1 * 4.0);
    float w2 = sin(d2 * freq - speed * 1.1 + 1.0) / (1.0 + d2 * 4.0);
    float w3 = sin(d3 * freq * 0.8 - speed * 0.9 + 2.0) / (1.0 + d3 * 5.0);
    float w4 = sin(d4 * freq * 1.2 - speed * 1.2 + 3.0) / (1.0 + d4 * 3.0);

    float combined = (w1 + w2 + w3 + w4);
    float brightness = combined * 0.5 + 0.5;
    float peak = pow(max(0.0, combined * 0.5 + 0.3), 4.0);
    float srcGlow = exp(-d1 * 6.0) + exp(-d2 * 6.0) + exp(-d3 * 6.0) + exp(-d4 * 6.0);

    float lum = clamp(brightness * brightness + peak * 0.5 + srcGlow * 0.15, 0.0, 1.0);
    return float4(lum, lum, lum, 0.8);
}

// ============================================================
// Video Rainbow — luminance pattern for video color tinting
// ============================================================
float4 videoRainbowPattern(float2 uv, float t, float intensity) {
    float2 center = uv - 0.5;
    float dist = length(center);
    float angle = atan2(center.y, center.x);

    float n = fbm(uv * 3.0 * intensity + float2(t * 0.2));

    float hue = fract(angle / (M_PI_F * 2.0) + dist * 3.0 * intensity + n * 0.5 - t * 0.3);
    // Convert hue cycle to luminance wave
    float lum = 0.5 + 0.5 * sin(hue * M_PI_F * 2.0);

    // Add swirl distortion
    float swirl = sin(dist * 10.0 * intensity - t * 2.0 + n * 5.0) * 0.5 + 0.5;
    lum *= 0.7 + swirl * 0.3;

    lum = clamp(lum, 0.0, 1.0);
    return float4(lum, lum, lum, 0.8);
}

// ============================================================
// Video Aurora — luminance pattern for video color tinting
// ============================================================
float4 videoAuroraPattern(float2 uv, float t, float intensity) {
    float2 p = uv * 2.0 * intensity;

    // Vertical curtain waves
    float curtain1 = sin(p.x * 3.0 + t * 0.5 + fbm(float2(p.x * 2.0, t * 0.3)) * 3.0);
    float curtain2 = sin(p.x * 5.0 - t * 0.3 + fbm(float2(p.x * 1.5, t * 0.2 + 5.0)) * 2.0);
    float curtain3 = sin(p.x * 7.0 + t * 0.7 + fbm(float2(p.x * 3.0, t * 0.15 + 10.0)) * 1.5);

    // Vertical fade
    float vertFade = smoothstep(0.0, 0.8, uv.y) * smoothstep(1.0, 0.6, uv.y);

    // Flowing noise
    float n1 = fbm(p + float2(t * 0.2, t * 0.1));
    float n2 = fbm(p * 1.3 + float2(-t * 0.15, t * 0.25) + n1);

    // Layer intensities
    float layer1 = pow(max(0.0, 0.5 + curtain1 * 0.5), 3.0) * vertFade;
    float layer2 = pow(max(0.0, 0.5 + curtain2 * 0.5), 4.0) * vertFade;
    float layer3 = pow(max(0.0, 0.5 + curtain3 * 0.5), 5.0) * vertFade;

    // Combine layers into luminance
    float lum = layer1 * (0.8 + n1 * 0.4)
              + layer2 * (0.6 + n2 * 0.5)
              + layer3 * 0.7
              + layer1 * layer2 * 0.5;

    // Shimmer
    float shimmer = sin(p.x * 20.0 + p.y * 10.0 + t * 4.0) * 0.5 + 0.5;
    lum += 0.1 * shimmer * vertFade * n1;

    lum = clamp(lum, 0.0, 1.0);
    return float4(lum, lum, lum, 0.85);
}

kernel void generatePsychedelicTexture(
    texture2d<half, access::write> output [[texture(0)]],
    constant PsychedelicParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= uint(params.width) || gid.y >= uint(params.height)) return;

    float2 uv = float2(float(gid.x) / float(params.width),
                        float(gid.y) / float(params.height));

    float t = params.time * params.speed;

    float4 color;
    switch (params.styleIndex) {
        case 0: color = psychedelicPattern(uv, t, params.intensity); break;
        case 1: color = fractalPattern(uv, t, params.intensity); break;
        case 2: color = miku39Pattern(uv, t, params.intensity); break;
        case 3: color = rainbowPattern(uv, t, params.intensity); break;
        case 4: color = auroraPattern(uv, t, params.intensity); break;
        case 5: color = voronoiPattern(uv, t, params.intensity); break;
        case 6: color = interferencePattern(uv, t, params.intensity); break;
        case 7: color = hexTunnelPattern(uv, t, params.intensity); break;
        case 8: color = organicPattern(uv, t, params.intensity); break;
        case 9: color = sparklesPattern(uv, t, params.intensity); break;
        case 10: color = heartsPattern(uv, t, params.intensity); break;
        case 11: color = causticPattern(uv, t, params.intensity); break;
        case 12: color = videoPsychedelicPattern(uv, t, params.intensity); break;
        case 13: color = videoInterferencePattern(uv, t, params.intensity); break;
        case 14: color = videoRainbowPattern(uv, t, params.intensity); break;
        case 15: color = videoAuroraPattern(uv, t, params.intensity); break;
        default: color = psychedelicPattern(uv, t, params.intensity); break;
    }

    output.write(half4(color), gid);
}
