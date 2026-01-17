//
//  SpiralShaders.metal
//  HypnoticSpiral
//
//  Metal shaders for hypnotic spiral effects
//  These shaders are GLSL-style fragment shaders adapted for Metal
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniform Structures

struct ShaderUniforms {
    float time;
    float2 resolution;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex Shader (shared by all fragment shaders)

vertex VertexOut spiralVertexShader(uint vertexID [[vertex_id]]) {
    // Fullscreen quad vertices
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// MARK: - Utility Functions

float2 rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// MARK: - Hypnotic Spiral Shader
// Classic rotating spiral with configurable arms

fragment float4 hypnoticSpiralShader(VertexOut in [[stage_in]],
                                      constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float dist = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Spiral parameters
    float arms = 4.0;
    float twist = 8.0;
    float speed = uniforms.time * 2.0;

    // Create spiral pattern
    float spiral = sin(angle * arms + dist * twist - speed);
    spiral = smoothstep(-0.2, 0.2, spiral);

    // Fade at edges
    float fade = 1.0 - smoothstep(0.8, 1.2, dist);

    // Apply color
    float3 col = uniforms.color.rgb * spiral * fade;

    return float4(col, spiral * fade * uniforms.color.a);
}

// MARK: - Tunnel Shader
// Smooth tunnel effect with anti-aliased rings

fragment float4 tunnelShader(VertexOut in [[stage_in]],
                              constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 fragCoord = in.texCoord * uniforms.resolution;
    float2 centre = uniforms.resolution / 2.0;

    float4 col = float4(0.0, 0.0, 0.0, 1.0);

    float steps = 16.0;

    // Anti-aliasing loop
    for (float x = -(steps / 2.0); x < (steps / 2.0); x++) {
        for (float y = -(steps / 2.0); y < (steps / 2.0); y++) {
            float dist = sqrt(sqrt(distance(fragCoord + float2(x, y) / steps, centre)) * 100.0);
            col += floor(fmod(dist - uniforms.time * 3.0, 2.0));
        }
    }

    col /= steps * steps;

    // Fade towards edges
    float edgeFade = 1.0 - (distance(fragCoord, centre) / uniforms.resolution.x);

    float3 finalCol = col.rgb * uniforms.color.rgb * edgeFade;

    return float4(finalCol, col.r * edgeFade * uniforms.color.a);
}

// MARK: - Chromatic Vortex Shader
// RGB separation with swirling motion

fragment float4 chromaticVortexShader(VertexOut in [[stage_in]],
                                       constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float dist = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Chromatic aberration offsets
    float offset = 0.02 * dist;
    float2 uvR = rotate2D(uv, offset) * (1.0 + offset);
    float2 uvB = rotate2D(uv, -offset) * (1.0 - offset);

    // Individual channel spirals
    float arms = 3.0;
    float twist = 10.0;
    float speed = uniforms.time * 1.5;

    float distR = length(uvR);
    float distB = length(uvB);
    float angleR = atan2(uvR.y, uvR.x);
    float angleB = atan2(uvB.y, uvB.x);

    float spiralR = sin(angleR * arms + distR * twist - speed) * 0.5 + 0.5;
    float spiralG = sin(angle * arms + dist * twist - speed) * 0.5 + 0.5;
    float spiralB = sin(angleB * arms + distB * twist - speed) * 0.5 + 0.5;

    // Fade at edges
    float fade = 1.0 - smoothstep(0.7, 1.1, dist);

    float3 col = float3(spiralR, spiralG, spiralB) * uniforms.color.rgb * fade;

    return float4(col, fade * uniforms.color.a);
}

// MARK: - Pulsing Rings Shader
// Concentric rings that pulse outward

fragment float4 pulsingRingsShader(VertexOut in [[stage_in]],
                                    constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float dist = length(uv);

    // Multiple ring frequencies
    float rings1 = sin(dist * 20.0 - uniforms.time * 3.0);
    float rings2 = sin(dist * 15.0 - uniforms.time * 2.5 + 1.0);
    float rings3 = sin(dist * 25.0 - uniforms.time * 3.5 + 2.0);

    // Combine rings with different weights
    float pattern = rings1 * 0.5 + rings2 * 0.3 + rings3 * 0.2;
    pattern = smoothstep(-0.1, 0.3, pattern);

    // Pulse intensity
    float pulse = sin(uniforms.time * 0.5) * 0.3 + 0.7;

    // Fade at center and edges
    float fade = smoothstep(0.0, 0.1, dist) * (1.0 - smoothstep(0.9, 1.2, dist));

    float3 col = uniforms.color.rgb * pattern * pulse * fade;

    return float4(col, pattern * fade * uniforms.color.a);
}

// MARK: - Fractal Spiral Shader
// Self-similar spiral patterns

fragment float4 fractalSpiralShader(VertexOut in [[stage_in]],
                                     constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float pattern = 0.0;
    float scale = 1.0;

    // Multiple octaves of spirals
    for (int i = 0; i < 4; i++) {
        float2 p = uv * scale;
        float dist = length(p);
        float angle = atan2(p.y, p.x);

        float arms = 2.0 + float(i);
        float twist = 6.0 + float(i) * 2.0;
        float speed = uniforms.time * (1.0 + float(i) * 0.3);

        float spiral = sin(angle * arms + dist * twist - speed);
        spiral = smoothstep(-0.2, 0.2, spiral);

        pattern += spiral / scale;
        scale *= 2.0;
    }

    pattern = pattern * 0.3;

    // Fade at edges
    float fade = 1.0 - smoothstep(0.8, 1.2, length(uv));

    float3 col = uniforms.color.rgb * pattern * fade;

    return float4(col, pattern * fade * uniforms.color.a);
}

// MARK: - Hypno Eye Shader
// Eye-like hypnotic pattern

fragment float4 hypnoEyeShader(VertexOut in [[stage_in]],
                                constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float dist = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Iris pattern
    float iris = sin(angle * 12.0 + dist * 8.0 - uniforms.time * 2.0);
    iris = smoothstep(-0.3, 0.3, iris);

    // Pupil (dark center that pulses)
    float pupilSize = 0.15 + sin(uniforms.time * 0.7) * 0.05;
    float pupil = 1.0 - smoothstep(pupilSize - 0.05, pupilSize + 0.05, dist);

    // Outer ring
    float outer = smoothstep(0.6, 0.65, dist) * (1.0 - smoothstep(0.75, 0.8, dist));

    // Combine
    float pattern = iris * (1.0 - pupil) * (1.0 - smoothstep(0.6, 0.8, dist));
    pattern += outer * 0.5;

    float3 col = uniforms.color.rgb * pattern;

    return float4(col, pattern * uniforms.color.a);
}

// MARK: - Kaleidoscope Shader
// Symmetric kaleidoscope pattern

fragment float4 kaleidoscopeShader(VertexOut in [[stage_in]],
                                    constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float dist = length(uv);
    float angle = atan2(uv.y, uv.x);

    // Create kaleidoscope symmetry (8 segments)
    float segments = 8.0;
    float segmentAngle = 3.14159 * 2.0 / segments;
    angle = abs(fmod(angle + segmentAngle * 0.5, segmentAngle) - segmentAngle * 0.5);

    // Convert back to cartesian for pattern
    float2 p = float2(cos(angle), sin(angle)) * dist;

    // Moving pattern
    p += float2(sin(uniforms.time * 0.7), cos(uniforms.time * 0.5)) * 0.3;

    // Pattern layers
    float pattern1 = sin(p.x * 10.0 + uniforms.time) * sin(p.y * 10.0 + uniforms.time);
    float pattern2 = sin(length(p) * 15.0 - uniforms.time * 2.0);

    float pattern = (pattern1 + pattern2) * 0.5;
    pattern = smoothstep(-0.3, 0.3, pattern);

    // Fade at edges
    float fade = 1.0 - smoothstep(0.8, 1.1, dist);

    float3 col = uniforms.color.rgb * pattern * fade;

    return float4(col, pattern * fade * uniforms.color.a);
}

// MARK: - Wave Interference Shader
// Overlapping wave patterns

fragment float4 waveInterferenceShader(VertexOut in [[stage_in]],
                                        constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    // Multiple wave sources
    float2 source1 = float2(sin(uniforms.time * 0.5) * 0.3, cos(uniforms.time * 0.3) * 0.3);
    float2 source2 = float2(cos(uniforms.time * 0.4) * 0.3, sin(uniforms.time * 0.6) * 0.3);
    float2 source3 = float2(0.0, 0.0);

    float wave1 = sin(length(uv - source1) * 20.0 - uniforms.time * 4.0);
    float wave2 = sin(length(uv - source2) * 18.0 - uniforms.time * 3.5);
    float wave3 = sin(length(uv - source3) * 22.0 - uniforms.time * 4.5);

    float pattern = (wave1 + wave2 + wave3) / 3.0;
    pattern = smoothstep(-0.2, 0.2, pattern);

    // Fade at edges
    float fade = 1.0 - smoothstep(0.9, 1.2, length(uv));

    float3 col = uniforms.color.rgb * pattern * fade;

    return float4(col, pattern * fade * uniforms.color.a);
}

// MARK: - Ripple Shader
// Colorful ripple distortion effect

fragment float4 rippleShader(VertexOut in [[stage_in]],
                              constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 center = float2(0.5, 0.5);
    float speed = 0.035;

    float invAr = uniforms.resolution.y / uniforms.resolution.x;

    float2 uv = in.texCoord;

    // Base color from UV coordinates and time
    float3 col = float3(uv.x, uv.y, 0.5 + 0.5 * sin(uniforms.time));

    // Calculate ripple
    float x = (center.x - uv.x);
    float y = (center.y - uv.y) * invAr;

    // Asymmetric ripple (use -sqrt(x*x + y*y) for symmetric)
    float r = -(x * x + y * y);
    float z = 1.0 + 0.5 * sin((r + uniforms.time * speed) / 0.013);

    float3 texcol = float3(z, z, z);

    // Blend with uniform color
    float3 finalCol = col * texcol * uniforms.color.rgb;

    return float4(finalCol, uniforms.color.a);
}

// MARK: - Dual Rings Shader
// Concentric rings moving both inward and outward

fragment float4 dualRingsShader(VertexOut in [[stage_in]],
                                 constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 coord = in.texCoord * uniforms.resolution;
    float2 center = uniforms.resolution / 2.0;

    float dist = length(center - coord);

    // Outward moving rings
    float circlesOut = cos(dist / 7.0 - uniforms.time * 6.0);
    circlesOut *= 5.0;

    // Inward moving rings
    float circlesIn = cos(dist / 7.0 + uniforms.time * 6.0);
    circlesIn *= 5.0;

    circlesIn = clamp(circlesIn, 0.0, 1.0);
    circlesOut = clamp(circlesOut, 0.0, 1.0);

    // Edge blending - outer rings fade out, inner rings fade in
    float edge = clamp(dist - 100.0, 0.0, 1.0);
    circlesOut *= edge;
    circlesIn *= 1.0 - edge;

    float c = circlesOut + circlesIn;

    // Apply uniform color
    float3 col = float3(c, c, c) * uniforms.color.rgb;

    return float4(col, c * uniforms.color.a);
}

// MARK: - Rainbow Shader
// Rainbow spiral with logarithmic polar coordinates

float3 rainbowPalette(float g) {
    float f = 6.0; // factor
    float3 o = float3(0.5, 0.75, 1.0); // offset
    o -= (o.r + o.g + o.b) / 3.0; // center (subtract average)
    return 0.5 + 0.5 * -cos(f * (g / f + o));
}

fragment float4 rainbowShader(VertexOut in [[stage_in]],
                               constant ShaderUniforms &uniforms [[buffer(0)]]) {
    float2 uv = (in.texCoord - 0.5) * uniforms.resolution / uniforms.resolution.y;

    // Convert to polar coordinates
    float2 pv = float2(atan2(uv.x, uv.y), length(uv));
    pv.y = log2(pv.y);
    pv -= uniforms.time;
    pv *= 3.0;

    float3 col = rainbowPalette(pv.x + pv.y);

    return float4(col * uniforms.color.rgb, uniforms.color.a);
}
