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
uniform float uZoom;        // 18   view zoom (UV-space, keeps render crisp)
uniform vec2 uPan;          // 19,20 view pan in UV

uniform sampler2D uHeight;  // sampler 0
uniform sampler2D uAlbedo;  // sampler 1

out vec4 fragColor;

// Nearest decode of the 16-bit packed height at a texel.
float decodeHeight(vec2 uv) {
  vec4 c = texture(uHeight, clamp(uv, vec2(0.0), vec2(1.0)));
  return (c.r * 255.0 * 256.0 + c.g * 255.0) / 65535.0;
}

// Bilinear height: decode the 4 surrounding texels and blend. (Can't let the
// sampler filter the packed bytes — it would interpolate hi/lo channels wrong.)
float decodeHeightBilinear(vec2 uv) {
  vec2 tx = 1.0 / uGridSize;
  vec2 p = uv * uGridSize - 0.5;
  vec2 f = fract(p);
  vec2 base = (floor(p) + 0.5) * tx;
  float h00 = decodeHeight(base);
  float h10 = decodeHeight(base + vec2(tx.x, 0.0));
  float h01 = decodeHeight(base + vec2(0.0, tx.y));
  float h11 = decodeHeight(base + vec2(tx.x, tx.y));
  return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

void main() {
  // Zoom/pan in UV so the shader resamples the grid at the zoomed level (crisp
  // per-pixel lighting) instead of magnifying a low-res raster.
  vec2 uv = FlutterFragCoord().xy / uResolution;
  uv = (uv - 0.5) / uZoom + 0.5 + uPan;
  vec2 texel = 1.0 / uGridSize;

  float hC = decodeHeightBilinear(uv);
  float hL = decodeHeightBilinear(uv - vec2(texel.x, 0.0));
  float hR = decodeHeightBilinear(uv + vec2(texel.x, 0.0));
  float hD = decodeHeightBilinear(uv - vec2(0.0, texel.y));
  float hU = decodeHeightBilinear(uv + vec2(0.0, texel.y));

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

  // Bilinear albedo so colour stays smooth when zoomed in.
  vec2 ap = uv * uGridSize - 0.5;
  vec2 af = fract(ap);
  vec2 abase = (floor(ap) + 0.5) * texel;
  vec3 a00 = texture(uAlbedo, clamp(abase, vec2(0.0), vec2(1.0))).rgb;
  vec3 a10 = texture(uAlbedo, clamp(abase + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
  vec3 a01 = texture(uAlbedo, clamp(abase + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb;
  vec3 a11 = texture(uAlbedo, clamp(abase + texel, vec2(0.0), vec2(1.0))).rgb;
  vec3 albedo = mix(mix(a00, a10, af.x), mix(a01, a11, af.x), af.y);
  float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
  albedo = max(vec3(0.0), mix(vec3(luma), albedo, uSaturation));

  vec3 diffuse = albedo * (keyDiff + fillDiff);
  vec3 color = (amb * albedo + diffuse) * ao + vec3(spec + sheen + fres);

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
