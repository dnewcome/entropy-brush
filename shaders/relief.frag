#version 460 core
#include <flutter/runtime_effect.glsl>

// Relief lighting for the impasto canvas — a richer material so the paint reads
// as wet, dimensional oil:
//  - normals reconstructed from the height field
//  - cavity ambient occlusion: crevices between strokes darken (tactile depth)
//  - hemispheric ambient + key + fill lights (dimension, not flat Lambert)
//  - wet glossy specular + broad sheen + fresnel edge (oily highlights)

precision highp float;

uniform vec2 uResolution;   // 0,1  output rect size in px
uniform vec2 uGridSize;     // 2,3  texture resolution
uniform vec3 uLightDir;     // 4,5,6 direction TO the key light
uniform float uHeightScale; // 7    relief exaggeration
uniform float uAmbient;     // 8
uniform float uSpecular;    // 9
uniform float uShininess;   // 10
uniform vec3 uViewDir;      // 11,12,13 direction to camera (tilt)
uniform float uOcclusion;   // 14   cavity AO strength
uniform float uGloss;       // 15   wet sheen amount
uniform float uFill;        // 16   fill-light strength
uniform float uSaturation;  // 17   colour richness

uniform sampler2D uHeight;  // sampler 0
uniform sampler2D uAlbedo;  // sampler 1

out vec4 fragColor;

float decodeHeight(vec2 uv) {
  vec4 c = texture(uHeight, clamp(uv, vec2(0.0), vec2(1.0)));
  return (c.r * 255.0 * 256.0 + c.g * 255.0) / 65535.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uResolution;
  vec2 texel = 1.0 / uGridSize;

  float hC = decodeHeight(uv);
  float hL = decodeHeight(uv - vec2(texel.x, 0.0));
  float hR = decodeHeight(uv + vec2(texel.x, 0.0));
  float hD = decodeHeight(uv - vec2(0.0, texel.y));
  float hU = decodeHeight(uv + vec2(0.0, texel.y));

  float dhdx = (hR - hL) * 0.5 * uHeightScale;
  float dhdy = (hU - hD) * 0.5 * uHeightScale;
  vec3 N = normalize(vec3(-dhdx, -dhdy, 1.0));

  // Cavity AO: sum how much the surroundings rise above this point. Points in
  // crevices (surroundings higher) get occluded and darken.
  vec2 r1 = texel * 2.5;
  float occ = 0.0;
  occ += max(0.0, decodeHeight(uv + vec2(r1.x, 0.0)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(-r1.x, 0.0)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(0.0, r1.y)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(0.0, -r1.y)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(r1.x, r1.y)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(-r1.x, r1.y)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(r1.x, -r1.y)) - hC);
  occ += max(0.0, decodeHeight(uv + vec2(-r1.x, -r1.y)) - hC);
  occ = clamp(occ * 0.125 * uHeightScale * 0.4, 0.0, 1.0);
  float ao = 1.0 - uOcclusion * occ;

  vec3 L = normalize(uLightDir);
  float keyDiff = max(dot(N, L), 0.0);

  // Fill light from a complementary, raised direction.
  vec3 Lf = normalize(vec3(-L.x * 0.5, -L.y * 0.5, 0.9));
  float fillDiff = max(dot(N, Lf), 0.0) * uFill;

  // Hemispheric ambient: cool sky from above, warm bounce from below.
  vec3 sky = vec3(0.60, 0.66, 0.78);
  vec3 ground = vec3(0.55, 0.45, 0.34);
  vec3 amb = mix(ground, sky, N.z * 0.5 + 0.5) * uAmbient;

  // Wet specular: a tight glossy hotspot + a broad sheen + a fresnel edge.
  vec3 V = normalize(uViewDir);
  vec3 H = normalize(L + V);
  float ndh = max(dot(N, H), 0.0);
  float sh = uShininess * (1.0 + 4.0 * uGloss);
  float spec = pow(ndh, sh) * uSpecular * (0.5 + uGloss);
  float sheen = pow(ndh, 6.0) * uGloss * 0.25;
  float fres = pow(1.0 - max(dot(N, V), 0.0), 4.0) * uGloss * 0.4;

  vec3 albedo = texture(uAlbedo, uv).rgb;
  float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
  albedo = max(vec3(0.0), mix(vec3(luma), albedo, uSaturation));

  vec3 diffuse = albedo * (keyDiff + fillDiff);
  vec3 color = (amb * albedo + diffuse) * ao + vec3(spec + sheen + fres);

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
