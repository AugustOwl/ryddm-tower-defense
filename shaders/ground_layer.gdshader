shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// One translucent layer of the ground under the board. Several of these are stacked (see board.gd): the top one is
// the most transparent, each one below is more opaque, and the bottom of the stack is a solid color. Every layer
// runs the ground visualizer at its own scale, speed and phase, so the board's movement shows up at several depths
// and the camera's angle gives it parallax.
//
// viz_type 6 is the 16-bit waves layer (top of the ground). viz_type 5 is the DISCO FLOOR: the layer is cut into blocks, each block takes one of the (saturated) floor
// colors and follows ONE part of the music (bass, mids, highs or the bass hits). Every 30 seconds the blocks fade
// out and come back in a new shape (hexagons, squares, diamonds, ring segments) with a new random color and
// music-part assignment. The other types (rings, waves, ...) come from shaders/viz.gdshaderinc.

#include "res://shaders/viz.gdshaderinc"

global uniform float beat_pulse;
global uniform float beat_phase;
global uniform vec4 beat_color;
global uniform float audio_bass;
global uniform float audio_mid;
global uniform float audio_treble;
global uniform float audio_texture;
global uniform float color_drain;

uniform vec4 base_color : source_color = vec4(0.1, 0.12, 0.16, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.45, 0.75, 1.0);
uniform float layer_alpha = 0.2;      // how opaque this layer is (before the visualizer adds to it)
uniform float brightness = 0.5;       // visualizer strength
uniform int viz_type = 0;
uniform float pattern_scale = 1.0;    // pattern size: smaller = larger features
uniform float drift = 1.0;            // how fast this layer's pattern moves relative to the beat clock
uniform float phase_offset = 0.0;
// The disco palette: the floor tile colors, made more saturated (done in board.gd).
uniform vec4 disco_a : source_color = vec4(0.2, 0.35, 0.9, 1.0);
uniform vec4 disco_b : source_color = vec4(0.2, 0.35, 0.9, 1.0);
uniform vec4 disco_c : source_color = vec4(0.2, 0.35, 0.9, 1.0);
uniform vec4 disco_d : source_color = vec4(0.2, 0.35, 0.9, 1.0);
uniform vec4 disco_e : source_color = vec4(0.2, 0.35, 0.9, 1.0);
uniform float disco_block = 1.6;      // block size in (scaled) world units
uniform float disco_period = 30.0;    // seconds between new shapes / groupings
uniform float disco_coverage = 0.4;   // fraction of the blocks that are visible at a time (0..1)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Each returns vec3(cell id x, cell id y, distance to the cell's edge: 0 at the edge, 0.5 in the middle).
vec3 cell_hex(vec2 p, float s) {
	float q = (0.57735027 * p.x - 0.33333333 * p.y) / s;
	float r = (0.66666667 * p.y) / s;
	vec3 c = vec3(q, -q - r, r);
	vec3 rc = floor(c + 0.5);
	vec3 diff = abs(rc - c);
	if (diff.x > diff.y && diff.x > diff.z) {
		rc.x = -rc.y - rc.z;
	} else if (diff.y > diff.z) {
		rc.y = -rc.x - rc.z;
	} else {
		rc.z = -rc.x - rc.y;
	}
	vec3 f = c - rc;
	float m = max(abs(f.x - f.y), max(abs(f.x - f.z), abs(f.y - f.z)));
	return vec3(rc.x, rc.z, (1.0 - m) * 0.5);
}

vec3 cell_square(vec2 p, float s) {
	vec2 g = p / s;
	vec2 l = fract(g);
	return vec3(floor(g), min(min(l.x, 1.0 - l.x), min(l.y, 1.0 - l.y)));
}

vec3 cell_diamond(vec2 p, float s) {
	return cell_square(vec2(p.x + p.y, p.x - p.y) * 0.70710678, s);
}

vec3 cell_polar(vec2 p, float s) {
	float d = length(p) / s;
	float a = (atan(p.y, p.x) / 6.2831853 + 0.5) * 14.0;   // 14 segments around
	vec2 l = vec2(fract(d), fract(a));
	return vec3(floor(d), floor(a), min(min(l.x, 1.0 - l.x), min(l.y, 1.0 - l.y)));
}

vec3 palette_pick(float h) {
	int i = int(floor(h * 5.0));
	if (i <= 0) { return disco_a.rgb; }
	if (i == 1) { return disco_b.rgb; }
	if (i == 2) { return disco_c.rgb; }
	if (i == 3) { return disco_d.rgb; }
	return disco_e.rgb;
}

void fragment() {
	vec3 rgb = base_color.rgb;
	float alpha = layer_alpha;

	if (viz_type == 5) {
		float t = TIME / disco_period;
		float epoch = floor(t);
		float into = t - epoch;
		// Fade out at the end of a period and back in at the start of the next: the new shape appears while dark.
		float fade = smoothstep(0.0, 0.05, into) * (1.0 - smoothstep(0.95, 1.0, into));
		float seed = mod(epoch, 64.0) * 13.7 + phase_offset * 100.0;
		int shape = int(mod(epoch, 4.0));

		vec2 p = world_pos.xz * pattern_scale;
		vec3 cell;
		if (shape == 0) {
			cell = cell_hex(p, disco_block);
		} else if (shape == 1) {
			cell = cell_square(p, disco_block);
		} else if (shape == 2) {
			cell = cell_diamond(p, disco_block);
		} else {
			cell = cell_polar(p, disco_block);
		}

		float h_color = viz_hash(cell.xy + seed);
		float h_group = viz_hash(cell.xy * 1.37 + seed + 41.0);
		vec3 color = palette_pick(h_color);

		// Which part of the song this block follows: bass, mids, highs, or the bass hits.
		int group = int(floor(h_group * 4.0));
		float drive = audio_bass;
		if (group == 1) { drive = audio_mid; }
		else if (group == 2) { drive = audio_treble; }
		else if (group == 3) { drive = beat_pulse; }

		float lit = clamp((0.12 + 1.0 * drive) * brightness * 1.6, 0.0, 1.0) * fade;
		float block = smoothstep(0.02, 0.07, cell.z);      // thin dark grout between blocks
		rgb = mix(color * 0.18, color, lit);
		// Only some blocks are shown (a new random set each period); the rest are fully transparent.
		float shown = step(viz_hash(cell.xy * 0.73 + seed + 97.0), disco_coverage);
		alpha = clamp(layer_alpha * (0.4 + lit * 3.0), 0.0, 1.0) * mix(0.1, 1.0, block) * mix(0.35, 1.0, fade) * shown;
	} else if (viz_type == 6) {
		// 16-bit waves: the field is snapped to a coarse pixel grid and posterized to 4 colors, with faint scanlines.
		float px = 0.2;
		vec2 q = (floor(world_pos.xz * pattern_scale / px) + 0.5) * px;
		float t = (beat_phase * drift + phase_offset) * 6.2831853;
		float v = 0.5 + 0.25 * sin(q.x * 0.55 + t + sin(q.y * 0.4 - t) * 1.3)
				+ 0.25 * sin((q.x + q.y) * 0.3 - t * 2.0);
		v += audio_bass * 0.15 + beat_pulse * 0.1;           // swells with the music
		float band = floor(clamp(v, 0.0, 0.999) * 4.0);       // 0..3
		vec3 c = disco_b.rgb;
		if (band == 1.0) { c = disco_a.rgb; }
		else if (band == 2.0) { c = disco_c.rgb; }
		else if (band == 3.0) { c = disco_e.rgb; }
		float scan = mix(0.9, 1.0, mod(floor(world_pos.z * pattern_scale / px), 2.0));
		rgb = c * scan;
		alpha = clamp(layer_alpha * (0.3 + band * 0.45) * clamp(brightness * 2.0, 0.0, 2.0), 0.0, 1.0);
	} else {
		float pattern = viz_pattern(viz_type, world_pos * pattern_scale, beat_phase * drift + phase_offset, 5.0,
				audio_bass, audio_mid, audio_treble, audio_texture, TIME);
		float glow = clamp((pattern + beat_pulse * 0.1) * brightness, 0.0, 1.0);
		vec3 tint = mix(beat_color.rgb, warm_color.rgb, clamp(audio_mid * 0.8, 0.0, 1.0));
		rgb = mix(base_color.rgb, tint, glow * 0.7);
		alpha = clamp(layer_alpha * (0.6 + glow * 2.0), 0.0, 1.0);
	}

	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(rgb, vec3(grey), color_drain);
	ALPHA = alpha;
}
