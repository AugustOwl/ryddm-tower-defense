shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Glowing border strip along the edge of a side's territory. Pulses with the main beat; a soft wave
// travels along the border once per beat. UV.y runs across the strip (0..1) for the glow falloff.

global uniform float beat_pulse;
global uniform float beat_phase;
global uniform float event_pulse;
global uniform vec4 beat_color;

uniform vec4 tint : source_color = vec4(0.3, 0.65, 1.0, 1.0);
uniform float base_intensity = 0.7;
uniform float pulse_intensity = 1.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float glow_shape = pow(across, 2.0) + 0.5 * pow(across, 0.8);
	float wave = 0.5 + 0.5 * sin((world_pos.x + world_pos.z) * 1.2 - beat_phase * 6.2831853);
	float g = glow_shape * (base_intensity + pulse_intensity * beat_pulse + event_pulse) * (0.75 + 0.25 * wave);
	ALBEDO = mix(tint.rgb, beat_color.rgb, 0.25) * g;
	ALPHA = 1.0;
}
