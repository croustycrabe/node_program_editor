#version 460 core

// Infinite, zoom-adaptive canvas grid rendered in a single draw call.
//
// The grid is computed analytically per fragment so its cost is independent
// of the number of grid cells on screen (unlike a CPU loop of drawCircle /
// drawLine calls).

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;        // Size of the painted rect, logical px.
uniform vec2 uOffset;      // Viewport translation, logical px.
uniform float uZoom;       // Viewport zoom.
uniform float uSpacing;    // Minor grid spacing, canvas units.
uniform float uMajorEvery; // Major line every N minor cells (<= 1 disables).
uniform float uStyle;      // 0 = dots, 1 = lines, 2 = cross.
uniform float uThickness;  // Dot radius / line width, logical px.
uniform vec4 uColor;       // Minor color (straight alpha).
uniform vec4 uMajorColor;  // Major color (straight alpha).

out vec4 fragColor;

// Distance in screen pixels from canvas point `c` to the nearest grid line,
// per axis, for a grid of `step` canvas units.
vec2 axisDistance(vec2 c, float step) {
  vec2 g = c / step;
  return abs(fract(g + 0.5) - 0.5) * step * uZoom;
}

float coverage(vec2 d, float thickness) {
  if (uStyle < 0.5) {
    // Dots.
    float r = length(d);
    return 1.0 - smoothstep(thickness - 0.5, thickness + 0.5, r);
  } else if (uStyle < 1.5) {
    // Lines.
    float m = min(d.x, d.y);
    float hw = thickness * 0.5;
    return 1.0 - smoothstep(hw - 0.5, hw + 0.5, m);
  }
  // Cross: short arms at each intersection.
  float hw = thickness * 0.5;
  float arm = max(3.0, thickness * 4.0);
  float h = (1.0 - smoothstep(hw - 0.5, hw + 0.5, d.y)) *
            (1.0 - smoothstep(arm - 0.5, arm + 0.5, d.x));
  float v = (1.0 - smoothstep(hw - 0.5, hw + 0.5, d.x)) *
            (1.0 - smoothstep(arm - 0.5, arm + 0.5, d.y));
  return max(h, v);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 c = (p - uOffset) / uZoom;

  // Double the spacing until cells are at least 8px on screen so dense
  // grids never alias into noise when zoomed out.
  float step = uSpacing;
  float screenStep = step * uZoom;
  float k = exp2(ceil(log2(max(1.0, 8.0 / max(screenStep, 0.0001)))));
  step *= k;
  screenStep = step * uZoom;

  // Fade minor grid in as it approaches the minimum density.
  float fade = clamp((screenStep - 8.0) / 8.0, 0.0, 1.0) * 0.6 + 0.4;

  float minor = coverage(axisDistance(c, step), uThickness) * fade;

  float major = 0.0;
  if (uMajorEvery > 1.0) {
    float majorStep = step * uMajorEvery;
    major = coverage(axisDistance(c, majorStep), uThickness * 1.5);
  }

  vec4 col = mix(uColor * minor, uMajorColor, major);
  float a = max(minor * uColor.a, major * uMajorColor.a);
  fragColor = vec4(col.rgb * a, a);
}
