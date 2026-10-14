//
//  HoloFoil.metal
//  DotaMind
//
//  Голографическая фольга для карточки игрока — как у редких
//  коллекционных карт: радужные полосы, блик и блёстки, которые
//  «переливаются» при наклоне телефона.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float3 hsv2rgb(float h, float s, float v) {
    float3 k = float3(1.0, 2.0 / 3.0, 1.0 / 3.0);
    float3 p = abs(fract(float3(h) + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

/// - size: размер карточки в точках
/// - tilt: наклон −1…1 (x — вправо, y — к себе)
/// - time: секунды, для медленного «дыхания» узора
/// - strength: общая интенсивность 0…1
[[ stitchable ]] half4 holoFoil(float2 position, half4 color, float2 size, float2 tilt, float time, float strength) {
    float2 uv = position / size;

    // Радужные диагональные полосы. Сдвиг по наклону даёт перелив.
    float band = (uv.x * 0.9 + uv.y * 1.4) * 1.6 + tilt.x * 0.8 - tilt.y * 0.6 + time * 0.03;
    float3 rainbow = hsv2rgb(fract(band), 0.6, 1.0);

    // Блик — «источник света» движется против наклона.
    float2 light = float2(0.5 - tilt.x * 0.55, 0.42 - tilt.y * 0.55);
    float glare = smoothstep(0.75, 0.0, distance(uv * float2(1.0, 1.35), light * float2(1.0, 1.35)));

    // Тонкая, еле заметная штриховка фольги.
    float lines = 0.88 + 0.12 * sin((position.x - position.y) * 1.6);

    // Блёстки: редкие ячейки, мерцающие в зависимости от угла.
    float2 cell = floor(position / 2.5);
    float h = hash21(cell);
    float twinkle = 0.5 + 0.5 * sin(h * 60.0 + tilt.x * 14.0 - tilt.y * 11.0 + time * 1.2);
    float sparkle = step(0.988, h) * pow(twinkle, 3.0) * (0.35 + glare);

    float foil = (0.18 + glare * 0.82) * lines;
    float3 rgb = rainbow * foil + float3(sparkle);
    float alpha = clamp(max(foil, sparkle), 0.0, 1.0) * strength;

    // SwiftUI ждёт premultiplied alpha.
    return half4(half3(rgb * alpha), half(alpha));
}
