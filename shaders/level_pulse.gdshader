shader_type spatial;
// Level surfaces (board tiles, walls and the large background plane) that react to the music.
// Everything here is driven by what the audio is doing, never by a tempo:
//   bass    pulses the glow and brightens the rings travelling outward from the board's center
//   mid     shifts the color toward a warm secondary hue
//   treble  makes small points of light flicker across the surface
//   texture ripples and warps the rings (busy, rough music = wobblier rings)

global uniform float beat_pulse;     // jumps on a detected bass hit
global uniform float beat_phase;     // flowing clock, faster when the music is louder
global uniform float event_pulse;
global uniform vec4 beat_color;
global uniform float audio_bass;
global uniform float audio_mid;
global uniform float audio_treble;
global uniform float audio_texture;
global uniform float color_drain;   // 0..1: set while deploying a tower; drains color so towers pop

uniform vec4 base_color : source_color = vec4(0.16, 0.19, 0.26, 1.0);
uniform float pulse_strength = 0.12;
uniform float ring_strength = 0.0;
uniform float ring_spacing = 5.0;
uniform float sparkle_strength = 0.0;
uniform vec4 warm_color : source_color = vec4(1.0, 0.45, 0.75, 1.0);

varying vec3 world_pos;

vec3 drain(vec3 c) {
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, vec3(grey), color_drain);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = drain(base_color.rgb);
	ROUGHNESS = 0.9;

	float d = length(world_pos.xz);
	float warp = audio_texture * 1.6 * sin(world_pos.x * 0.8 + world_pos.z * 1.1 + beat_phase * 6.2831853);
	float ring = pow(fract((d + warp) / ring_spacing - beat_phase), 10.0);

	vec3 tint = mix(beat_color.rgb, warm_color.rgb, clamp(audio_mid * 0.8, 0.0, 1.0));

	// Treble: tiny cells that flicker on and off, more of them the brighter the highs are.
	vec2 cell = floor(world_pos.xz * 3.0);
	float flicker = hash(cell + floor(TIME * 10.0));
	float sparkle = step(0.96 - audio_treble * 0.12, flicker) * audio_treble;

	float glow = pulse_strength * (audio_bass * 1.2 + beat_pulse * 0.8 + event_pulse)
		+ ring_strength * ring * exp(-d * 0.035) * (0.25 + 1.1 * audio_bass + 0.5 * audio_mid);
	EMISSION = drain(tint) * glow + vec3(1.0) * sparkle * sparkle_strength;
}
