/** @resolution */
uniform vec2 u_resolution;

/**
 * Number of cells per side (square grid).
 * @section Grid
 * @label Cells
 * @default 20.0
 * @range 4, 48
 * @step 1
 */
uniform float u_gridSize;

/**
 * Shape of individual cells.
 * @section Grid
 * @label Cell Shape
 * @select Square, Circle, Diamond, Hexagon, Star
 * @default 0
 */
uniform float u_cellShape;

/**
 * Space between cells as fraction of cell size.
 * @section Grid
 * @label Gap
 * @default 0.15
 * @range 0, 0.8
 */
uniform float u_gap;

/**
 * How much cell size varies by distance from center.
 * @section Falloff
 * @label Amount
 * @default 0.0
 * @range 0, 3
 */
uniform float u_falloff;

/**
 * Shapes the falloff curve.
 * @section Falloff
 * @label Curve
 * @envelope
 * @default 0, 0, 1, 1
 */
uniform sampler2D u_falloffCurve;

/**
 * Largest cell size (fraction of cell).
 * @section Falloff
 * @label Max Size
 * @default 1.0
 * @range 0.1, 2
 */
uniform float u_maxSize;

/**
 * Smallest cell size when falloff is applied.
 * @section Falloff
 * @label Min Size
 * @default 0.1
 * @range 0.01, 1
 */
uniform float u_minSize;

/**
 * Show grid lines at cell boundaries.
 * @section Grid
 * @label Show Grid
 * @switch
 * @default 0
 */
uniform float u_showGrid;

/**
 * @section Shape
 * @label Type
 * @select Circle, Square, Diamond, Hexagon, Star
 * @default 0
 */
uniform float u_shape;

/**
 * @section Shape
 * @label Mode
 * @select Ring, Filled
 * @default 0
 */
uniform float u_mode;

/**
 * Shape size relative to half the grid.
 * @section Shape
 * @label Radius
 * @default 0.35
 * @range 0.05, 0.5
 */
uniform float u_radius;

/**
 * Ring width in cells.
 * @section Shape
 * @label Thickness
 * @default 1.0
 * @range 0.5, 5
 */
uniform float u_thickness;

/**
 * Rotate the shape in degrees.
 * @section Shape
 * @label Rotation
 * @default 0.0
 * @range 0, 360
 */
uniform float u_rotation;

/**
 * @section Color
 * @label Color A
 * @color
 * @default #e8f48c
 */
uniform vec3 u_colorA;

/**
 * @section Color
 * @label Color B
 * @color
 * @default #d6b4fc
 */
uniform vec3 u_colorB;

/**
 * @section Color
 * @label Background
 * @color
 * @default #141418
 */
uniform vec3 u_bg;

float cellDist(vec2 p, float s) {
    float m = floor(s + 0.5);
    if (m < 0.5) return max(abs(p.x), abs(p.y));
    if (m < 1.5) return length(p);
    if (m < 2.5) return abs(p.x) + abs(p.y);
    if (m < 3.5) {
        vec2 a = abs(p);
        return max(a.x * 0.866025 + a.y * 0.5, a.y);
    }
    float a = atan(p.y, p.x);
    float sec = 6.2832 / 5.0;
    float hs = sec * 0.5;
    float la = mod(a + hs + 6.2832, sec) - hs;
    return length(p) / mix(1.0, 0.38, abs(la) / hs);
}

float shapeDist(vec2 p, float shapeType) {
    float m = floor(shapeType + 0.5);
    if (m < 0.5) {
        return length(p);
    }
    if (m < 1.5) {
        return max(abs(p.x), abs(p.y));
    }
    if (m < 2.5) {
        return abs(p.x) + abs(p.y);
    }
    if (m < 3.5) {
        vec2 a = abs(p);
        return max(a.x * 0.866025 + a.y * 0.5, a.y);
    }
    float angle = atan(p.y, p.x);
    float section = 6.2832 / 5.0;
    float halfSec = section * 0.5;
    float localA = mod(angle + halfSec + 6.2832, section) - halfSec;
    float edgeFactor = mix(1.0, 0.38, abs(localA) / halfSec);
    return length(p) / edgeFactor;
}

void main() {
    float gridN = floor(u_gridSize);

    float cellPx = min(u_resolution.x, u_resolution.y) / gridN;
    vec2 gridPx = vec2(gridN) * cellPx;
    vec2 origin = (u_resolution - gridPx) * 0.5;
    vec2 pos = (gl_FragCoord.xy - origin) / cellPx;

    vec2 baseID = floor(pos);
    vec2 baseUV = fract(pos);

    float rad = u_rotation * 3.14159 / 180.0;
    float cs = cos(rad);
    float sn = sin(rad);
    float modeF = floor(u_mode + 0.5);
    float halfThick = u_thickness / gridN * 0.5;

    float hitMask = 0.0;
    vec3 hitCol = u_bg;
    float hitPri = 999.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 nID = baseID + vec2(float(dx), float(dy));

            if (nID.x >= 0.0 && nID.y >= 0.0 && nID.x < gridN && nID.y < gridN) {
                vec2 nCenter = (nID + 0.5) / gridN - 0.5;
                vec2 rc = vec2(nCenter.x * cs - nCenter.y * sn,
                               nCenter.x * sn + nCenter.y * cs);

                float dist = shapeDist(rc, u_shape);

                float isOn;
                if (modeF < 0.5) {
                    isOn = step(u_radius - halfThick, dist)
                         * (1.0 - step(u_radius + halfThick, dist));
                } else {
                    isOn = 1.0 - step(u_radius, dist);
                }

                if (isOn > 0.5) {
                    float normDist = clamp(dist / max(u_radius, 0.001), 0.0, 1.0);
                    float curvedDist = texture2D(u_falloffCurve, vec2(normDist, 0.5)).r;
                    float falloffT = clamp(curvedDist * u_falloff, 0.0, 1.0);
                    float sizeScale = mix(u_maxSize, u_minSize, falloffT);
                    float halfSize = (1.0 - u_gap) * 0.5 * sizeScale;

                    vec2 pInCell = pos - nID - 0.5;
                    float d = cellDist(pInCell, u_cellShape);

                    float pw = fwidth(d) * 0.75;
                    float cellAlpha = 1.0 - smoothstep(halfSize - pw, halfSize + pw, d);
                    if (cellAlpha > 0.0 && d < hitPri) {
                        hitPri = d;
                        hitMask = cellAlpha;
                        float a = atan(nCenter.y, nCenter.x);
                        hitCol = mix(u_colorA, u_colorB, a / 6.2832 + 0.5);
                    }
                }
            }
        }
    }

    vec3 result = mix(u_bg, hitCol, hitMask);

    if (u_showGrid > 0.5) {
        float inGrid = step(0.0, baseID.x) * step(0.0, baseID.y)
                     * step(baseID.x, gridN - 1.0) * step(baseID.y, gridN - 1.0);
        float lineW = 1.0 / cellPx;
        float gpw = fwidth(baseUV.x) * 0.75;
        float onLineX = (1.0 - smoothstep(lineW - gpw, lineW + gpw, baseUV.x))
                       + smoothstep(1.0 - lineW - gpw, 1.0 - lineW + gpw, baseUV.x);
        float onLineY = (1.0 - smoothstep(lineW - gpw, lineW + gpw, baseUV.y))
                       + smoothstep(1.0 - lineW - gpw, 1.0 - lineW + gpw, baseUV.y);
        float gridLine = clamp(onLineX + onLineY, 0.0, 1.0) * inGrid;

        float bpw = fwidth(pos.x) * 0.75;
        float borderX = (1.0 - smoothstep(lineW - bpw, lineW + bpw, pos.x))
                       + smoothstep(gridN - lineW - bpw, gridN - lineW + bpw, pos.x);
        float borderY = (1.0 - smoothstep(lineW - bpw, lineW + bpw, pos.y))
                       + smoothstep(gridN - lineW - bpw, gridN - lineW + bpw, pos.y);
        float border = clamp(borderX + borderY, 0.0, 1.0) * inGrid;

        vec3 lineCol = mix(vec3(1.0), vec3(0.0), step(0.5, (u_bg.r + u_bg.g + u_bg.b) / 3.0));
        result = mix(result, lineCol * 0.25, gridLine * 0.5);
        result = mix(result, lineCol * 0.5, border * 0.7);
    }

    gl_FragColor = vec4(result, 1.0);
}
