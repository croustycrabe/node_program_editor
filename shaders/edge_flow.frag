#version 460 core

// Animated "data flowing" effect for edges. Used as Paint.shader on a stroked
// edge path: bright pulses march from source to target along the edge's
// dominant direction, giving an n8n / Node-RED style running indicator
// without any per-frame path measurement on the CPU.

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform float uTime;     // Seconds.
uniform vec2 uDir;       // Normalized source -> target direction (screen).
uniform float uSpacing;  // Pulse spacing, logical px.
uniform float uSpeed;    // Pulse speed, logical px / second.
uniform vec4 uColor;     // Base edge color (straight alpha).
uniform vec4 uPulse;     // Pulse color (straight alpha).

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float t = dot(p, uDir) - uTime * uSpeed;
  float f = fract(t / uSpacing);
  // Sharp leading edge, soft tail.
  float pulse = smoothstep(0.0, 0.35, f) * (1.0 - smoothstep(0.35, 0.55, f));
  vec4 c = mix(uColor, uPulse, pulse);
  fragColor = vec4(c.rgb * c.a, c.a);
}
