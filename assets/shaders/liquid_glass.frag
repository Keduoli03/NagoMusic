// 液态玻璃底栏着色器。
//
// 这是面向 Flutter RuntimeEffect 的独立实现，没有直接复制
// Kyant0/AndroidLiquidGlass 的 Compose/AGSL 源码；材质结构参考它公开的组合方式：
// vibrancy + blur + 圆角矩形透镜折射 + 色散 + 容器色 + 高光。
//
// 工作方式：它作为 BackdropFilter 的 ImageFilter 使用，uBackdrop 就是它身后
// 已经被引擎模糊过的画面（模糊交给 ImageFilter.blur 做，比在着色器里手写
// 高斯快得多，也更好看）。这里只负责「玻璃」那部分：把边缘附近的采样坐标
// 往里推，制造透镜的挤压感，再补上一道高光。
//
// dart:ui 的约定：第一个 uniform 必须是 vec2，且至少有一个 sampler。

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // 必须是第一个：绘制区域尺寸（像素）
uniform float uRadius;     // 圆角半径（像素）
uniform float uThickness;  // 折射带宽度（像素），从边缘往内算
uniform float uRefraction; // 折射强度：边缘处采样点最多往内挪多少像素
uniform float uDispersion; // 色散：R/B 通道的额外偏移量（像素），0 = 关闭
uniform float uHighlight;  // 高光强度 0~1
uniform float uEdgeShade;  // 边缘暗带强度 0~1
uniform float uSheen;      // 顶部光带强度 0~1
uniform float uVibrancy;   // 背景饱和度，1 = 原色
uniform float uTintAlpha;  // 叠色不透明度
uniform vec3 uTintColor;   // 叠色（线性 0~1）

uniform sampler2D uBackdrop;

out vec4 fragColor;

// 圆角矩形的有符号距离场。内部为负、边界为 0、外部为正。
float roundedBoxSdf(vec2 p, vec2 halfSize, float radius) {
    vec2 q = abs(p) - halfSize + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

vec2 clampUv(vec2 uv) {
    // 边缘附近的采样点会被推到区域外，钳制住避免采到垃圾像素（表现为边上一圈脏边）。
    return clamp(uv, vec2(0.0), vec2(1.0));
}

void main() {
    vec2 fragPos = FlutterFragCoord().xy;
    vec2 uv = fragPos / uSize;

    // OpenGLES 后端的纹理 y 轴是反的。
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif

    vec2 halfSize = uSize * 0.5;
    vec2 centered = fragPos - halfSize;
    float radius = min(uRadius, min(halfSize.x, halfSize.y));
    float dist = roundedBoxSdf(centered, halfSize, radius);

    // 完全在圆角外面的像素直接透传，不然圆角会被画成方的。
    if (dist > 0.0) {
        fragColor = texture(uBackdrop, clampUv(uv));
        return;
    }

    // depth: 边界处为 1，往里 uThickness 像素衰减到 0。
    float thickness = max(uThickness, 1.0);
    float depth = clamp(1.0 + dist / thickness, 0.0, 1.0);

    // 透镜剖面。用 depth 的平方让中心保持平坦、只有靠近边缘才明显弯折，
    // 线性的话整块面板都会糊成一片，不像玻璃像毛玻璃。
    float lens = depth * depth;

    // SDF 的梯度就是边缘的法线方向（朝外）。用中心差分求。
    float eps = 1.0;
    float dx = roundedBoxSdf(centered + vec2(eps, 0.0), halfSize, radius)
             - roundedBoxSdf(centered - vec2(eps, 0.0), halfSize, radius);
    float dy = roundedBoxSdf(centered + vec2(0.0, eps), halfSize, radius)
             - roundedBoxSdf(centered - vec2(0.0, eps), halfSize, radius);
    vec2 normal = vec2(dx, dy);
    float normalLen = length(normal);
    normal = normalLen > 0.0001 ? normal / normalLen : vec2(0.0, -1.0);

    // 往「内」推采样点（法线朝外，所以取负），制造边缘把背景吸进来的挤压感。
    vec2 offset = -normal * (uRefraction * lens);
    vec2 refractUv = clampUv(uv + offset / uSize);

    vec4 color;
    if (uDispersion > 0.001) {
        // 色散：三个通道错开一点点采样，边缘会出现极淡的彩边，是玻璃的关键细节。
        vec2 spread = -normal * (uDispersion * lens) / uSize;
        float r = texture(uBackdrop, clampUv(refractUv + spread)).r;
        vec4 g = texture(uBackdrop, refractUv);
        float b = texture(uBackdrop, clampUv(refractUv - spread)).b;
        color = vec4(r, g.g, b, g.a);
    } else {
        color = texture(uBackdrop, refractUv);
    }

    // AndroidLiquidGlass 的底栏会先做 vibrancy 再覆盖约 40% 的容器色。
    // 提升饱和度可以抵消模糊造成的灰雾感，让玻璃里的封面和背景仍有颜色。
    float luminance = dot(color.rgb, vec3(0.213, 0.715, 0.072));
    color.rgb = mix(vec3(luminance), color.rgb, uVibrancy);

    // 叠色既是染色，也是玻璃自己的材质层。没有它就只剩折射，看起来像完全透明。
    color.rgb = mix(color.rgb, uTintColor, uTintAlpha);

    // 边缘暗带。这是玻璃在**纯色背景上唯一可见的东西** —— 折射只是把背景挪个位置，
    // 背景本身是一片白的话，折射出来还是白的，等于什么都没发生。真实玻璃的边缘
    // 因为厚度会把光折走，形成一圈比中心暗的带子，轮廓靠它定形。
    float shadeBand = pow(depth, 2.5);
    color.rgb *= 1.0 - uEdgeShade * shadeBand;

    // 高光：光从左上来。法线朝外，所以 normal 与光方向反向的那一侧（左上边缘）最亮。
    vec2 lightDir = normalize(vec2(-0.6, -0.8));
    float facing = max(dot(normal, lightDir), 0.0);
    // 只在很窄的一条边上出现，用高次幂把它压窄。
    float rim = pow(depth, 6.0);
    float spec = facing * rim * uHighlight;
    color.rgb += vec3(spec);

    // 对侧补一道更弱的反光，玻璃才有厚度感。
    float backFacing = max(dot(normal, -lightDir), 0.0);
    color.rgb += vec3(backFacing * rim * uHighlight * 0.35);

    // 顶部光带。**背景是纯色时，玻璃主要靠这个被看见** —— 折射把一片白挪个位置
    // 还是一片白，但真实玻璃的弧面会把环境光聚成一条亮带，人眼正是靠它认出
    // 「这里有一块透明的东西」。从顶部往下快速衰减，只占上面三分之一。
    float yNorm = centered.y / halfSize.y * 0.5 + 0.5; // 0 = 顶, 1 = 底
    color.rgb += vec3(pow(1.0 - yNorm, 3.0) * uSheen);

    fragColor = color;
}
