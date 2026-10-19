// SPDX-License-Identifier: GPL-3.0-or-later

#include <metal_stdlib>
using namespace metal;

struct ScreenVertex {
    float4 position [[position]];
    float2 uv;
};

// Full-viewport quad as a 4-vertex triangle strip; the viewport selects the screen's rect.
vertex ScreenVertex screen_vertex(uint vid [[vertex_id]]) {
    const float2 uv = float2(vid & 1, (vid >> 1) & 1);
    ScreenVertex out;
    out.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    out.uv = uv;
    return out;
}

// Emulator pixels are BGRA with undefined alpha: always draw opaque.
fragment half4 screen_fragment(ScreenVertex in [[stage_in]],
                               texture2d<half> screen [[texture(0)]],
                               sampler smp [[sampler(0)]]) {
    return half4(screen.sample(smp, in.uv).rgb, 1.0h);
}
