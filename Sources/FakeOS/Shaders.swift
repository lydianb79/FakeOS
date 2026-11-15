// Metal shader source, compiled at runtime so the package needs no resource bundle.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 a; // screenW, screenH, time, haunt
    float4 b; // glitch, brightness, reveal, fade
    float4 c; // fade color
    float4 d; // calm, bloodWall, tear, unused
};

struct QuadIn {
    float4 rect;   // x, y, w, h in points
    float4 color;  // straight rgba
    float4 uv;     // u0 v0 u1 v1
    float4 params; // radius, mode, blur, alpha
};

struct VOut {
    float4 pos [[position]];
    float2 local;
    float2 uv;
    float2 screenPt;
};

float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash12(i), b = hash12(i + float2(1, 0)), c = hash12(i + float2(0, 1)), d = hash12(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float3 wallpaper(float2 uv, constant Uniforms& u) {
    float t = u.a.z * 0.035;
    float haunt = u.a.w;
    float calm = u.d.x;
    float blood = u.d.y;
    float2 p = uv;
    p.x *= u.a.x / max(u.a.y, 1.0);

    float w1 = sin(p.x * 2.1 + t + sin(p.y * 3.1 - t * 0.7) * 0.9);
    float w2 = sin(p.y * 2.6 - t * 0.8 + sin(p.x * 1.6 + t) * 1.2);
    float w3 = sin((p.x + p.y) * 1.8 + t * 0.5 + sin(p.y * 4.0 + t * 0.3) * 0.5);
    float v = (w1 + w2 + w3) / 3.0 * 0.5 + 0.5;
    float ribbon = smoothstep(0.42, 0.5, v) * (1.0 - smoothstep(0.5, 0.62, v));

    float3 deep   = float3(0.04, 0.07, 0.24);
    float3 indigo = float3(0.20, 0.17, 0.55);
    float3 violet = float3(0.55, 0.30, 0.72);
    float3 peach  = float3(0.98, 0.62, 0.55);
    float3 col = mix(deep, indigo, smoothstep(0.15, 0.55, v));
    col = mix(col, violet, smoothstep(0.5, 0.8, v));
    col = mix(col, peach, smoothstep(0.78, 1.0, v) * 0.85);
    col += ribbon * float3(0.25, 0.22, 0.35);
    col += (1.0 - uv.y) * float3(0.05, 0.04, 0.08);

    // haunted: drain the colour, push it towards bruise tones
    float lum = dot(col, float3(0.3, 0.59, 0.11));
    float3 sick = float3(lum * 0.95, lum * 0.62, lum * 0.66);
    col = mix(col, sick * 0.75, clamp(haunt * 0.85, 0.0, 1.0));
    // a slow dark shape that drifts under everything when the haunting is strong
    float2 c = float2(0.5 + 0.25 * sin(t * 2.0), 0.55 + 0.1 * cos(t * 1.3));
    float2 dp = (uv - c) * float2(u.a.x / max(u.a.y, 1.0), 1.0);
    float shade = exp(-dot(dp, dp) * 9.0) * (0.6 + 0.4 * vnoise(uv * 6.0 + t * 3.0));
    col *= 1.0 - shade * smoothstep(0.35, 1.0, haunt) * 0.8;

    // ending: bleed red
    float3 red = float3(0.35, 0.02, 0.03) * (0.6 + 0.6 * v);
    col = mix(col, red, blood);

    // good ending: dawn
    float3 dawn = mix(float3(0.98, 0.78, 0.62), float3(0.45, 0.62, 0.92), smoothstep(0.0, 1.0, uv.y + (v - 0.5) * 0.4));
    col = mix(col, dawn, calm);
    return col;
}

float sdRoundRect(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vertex VOut quad_vs(uint vid [[vertex_id]],
                    constant QuadIn& q [[buffer(0)]],
                    constant Uniforms& u [[buffer(1)]]) {
    float2 corner = float2(float(vid & 1), float(vid >> 1));
    float pad = (q.params.y == 2.0) ? q.params.z * 2.0 + 2.0 : 1.0;
    float2 p0 = q.rect.xy - pad;
    float2 sz = q.rect.zw + pad * 2.0;
    float2 pt = p0 + corner * sz;
    VOut o;
    o.pos = float4(pt.x / u.a.x * 2.0 - 1.0, 1.0 - pt.y / u.a.y * 2.0, 0.0, 1.0);
    o.local = pt - q.rect.xy;
    float2 t = (pt - q.rect.xy) / max(q.rect.zw, float2(0.0001));
    o.uv = mix(q.uv.xy, q.uv.zw, t);
    o.screenPt = pt;
    return o;
}

fragment float4 quad_fs(VOut in [[stage_in]],
                        constant QuadIn& q [[buffer(0)]],
                        constant Uniforms& u [[buffer(1)]],
                        texture2d<float> tex [[texture(0)]],
                        sampler s [[sampler(0)]]) {
    float2 halfSize = q.rect.zw * 0.5;
    float d = sdRoundRect(in.local - halfSize, halfSize, q.params.x);
    int mode = int(q.params.y + 0.5);
    float alpha = q.params.w;

    if (mode == 2) { // soft shadow
        float blur = max(q.params.z, 0.5);
        float a = 1.0 - smoothstep(-blur, blur * 1.6, d);
        a = a * a;
        return float4(0.0, 0.0, 0.0, 1.0) * a * q.color.a * alpha;
    }
    if (mode == 4) { // wallpaper
        float3 w = wallpaper(in.screenPt / u.a.xy, u);
        return float4(w, 1.0) * alpha;
    }

    float aa = 1.0 - smoothstep(-0.6, 0.6, d);
    float4 c;
    if (mode == 1) {
        float4 t = tex.sample(s, in.uv);
        c = t * q.color.a;
        c.rgb *= q.color.rgb;
    } else if (mode == 3) { // frosted glass over the wallpaper
        float3 w = wallpaper(in.screenPt / u.a.xy, u);
        float lum = dot(w, float3(0.3, 0.59, 0.11));
        w = mix(float3(lum), w, 0.65);
        float3 col = mix(w, q.color.rgb, q.color.a);
        c = float4(col, 1.0);
    } else {
        c = float4(q.color.rgb * q.color.a, q.color.a);
    }
    return c * aa * alpha;
}

struct PostOut {
    float4 pos [[position]];
    float2 uv;
};

vertex PostOut post_vs(uint vid [[vertex_id]]) {
    float2 c = float2(float(vid & 1), float(vid >> 1));
    PostOut o;
    o.pos = float4(c.x * 2.0 - 1.0, 1.0 - c.y * 2.0, 0.0, 1.0);
    o.uv = c;
    return o;
}

fragment float4 post_fs(PostOut in [[stage_in]],
                        constant Uniforms& u [[buffer(0)]],
                        texture2d<float> scene [[texture(0)]],
                        texture2d<float> ghost [[texture(1)]],
                        sampler s [[sampler(0)]]) {
    float2 uv = in.uv;
    float time = u.a.z;
    float haunt = u.a.w;
    float g = u.b.x;
    float tear = u.d.z;

    // horizontal slice displacement (digital glitch)
    float frame = floor(time * 24.0);
    float band = floor(uv.y * 36.0 + hash12(float2(frame, 1.0)) * 7.0);
    float n = hash12(float2(band, frame));
    if (n > 1.0 - g * 0.55) {
        uv.x += (hash12(float2(band, frame + 3.1)) - 0.5) * 0.09 * g;
    }
    // a single rolling tear line
    float tearY = fract(time * 0.37);
    float tearBand = 1.0 - smoothstep(0.0, 0.012, abs(uv.y - tearY));
    uv.x += tearBand * tear * 0.03 * sin(time * 40.0);

    // faint wobble when haunted
    uv.x += sin(uv.y * 28.0 + time * 1.7) * 0.0006 * haunt;

    float split = 0.007 * g + 0.0007 * haunt;
    float r = scene.sample(s, uv + float2(split, 0.0)).r;
    float gg = scene.sample(s, uv).g;
    float b = scene.sample(s, uv - float2(split, split * 0.3)).b;
    float3 col = float3(r, gg, b);

    // static
    float nz = hash12(in.uv * u.a.xy * 1.7 + float2(frame * 13.1, frame * 7.7)) - 0.5;
    col += nz * (0.28 * g + 0.018 * haunt);
    // scanline flicker during glitches
    col *= 1.0 - g * 0.18 * (0.5 + 0.5 * sin(in.uv.y * u.a.y * 1.5));

    // display brightness
    col *= u.b.y;

    // the writing that only shows in the dark
    float reveal = u.b.z;
    if (reveal > 0.001) {
        float4 gh0 = ghost.sample(s, in.uv);
        float4 gh1 = ghost.sample(s, in.uv, level(3.0));
        float4 gh2 = ghost.sample(s, in.uv, level(5.0));
        float flick = 0.82 + 0.18 * sin(time * 11.0) * sin(time * 6.3 + 1.0);
        float3 glow = gh0.rgb * 1.1 + gh1.rgb * 1.4 + gh2.rgb * 1.8;
        col += glow * reveal * flick;
    }

    // vignette
    float2 dv = in.uv - 0.5;
    col *= 1.0 - dot(dv, dv) * (0.15 + 0.9 * haunt);

    // fades
    col = mix(col, u.c.rgb, clamp(u.b.w, 0.0, 1.0));
    return float4(col, 1.0);
}
"""
