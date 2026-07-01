/** @resolution */
uniform vec2 u_resolution;

/**
 * Number of cells per side (square grid).
 * @section Grid
 * @label Cells
 * @default 20.0
 * @range 4, 48
 */
uniform float u_gridSize;

/**
 * Space between cells as fraction of cell size.
 * @section Grid
 * @label Gap
 * @default 0.15
 * @range 0, 0.8
 */
uniform float u_gap;

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

    vec2 cellID = floor(pos);
    vec2 cellUV = fract(pos);

    float inGrid = step(0.0, cellID.x) * step(0.0, cellID.y)
                 * step(cellID.x, gridN - 1.0) * step(cellID.y, gridN - 1.0);

    vec2 center = (cellID + 0.5) / gridN - 0.5;

    float rad = u_rotation * 3.14159 / 180.0;
    float c = cos(rad);
    float sn = sin(rad);
    vec2 rc = vec2(center.x * c - center.y * sn, center.x * sn + center.y * c);

    float dist = shapeDist(rc, u_shape);
    float halfThick = u_thickness / gridN * 0.5;

    float modeF = floor(u_mode + 0.5);
    float isOn;
    if (modeF < 0.5) {
        isOn = step(u_radius - halfThick, dist) * (1.0 - step(u_radius + halfThick, dist));
    } else {
        isOn = 1.0 - step(u_radius, dist);
    }

    float g = u_gap * 0.5;
    float cellVis = step(g, cellUV.x) * step(cellUV.x, 1.0 - g)
                  * step(g, cellUV.y) * step(cellUV.y, 1.0 - g);

    float angle = atan(center.y, center.x);
    float t = angle / 6.2832 + 0.5;
    vec3 col = mix(u_colorA, u_colorB, t);

    float mask = inGrid * isOn * cellVis;
    gl_FragColor = vec4(mix(u_bg, col, mask), 1.0);
}
