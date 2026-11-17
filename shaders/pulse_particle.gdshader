shader_type spatial;
render_mode unshaded, blend_add, shadows_disabled, depth_draw_never;
// Shared material for ALL particles in the game, so they pulse in step with the outlines and the level.
// Particle fade-out comes from the particle's color ramp alpha (COLOR.a).

global uniform float beat_pulse;
global uniform float event_pulse;
global uniform vec4 beat_color;
global uniform float color_drain;   // drained to grey while deploying a tower

void vertex() {
	VERTEX *= 1.0 + 0.6 * beat_pulse;
}

void fragment() {
	float grey = dot(beat_color.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(beat_color.rgb, vec3(grey), color_drain) * (1.0 + 1.5 * beat_pulse + event_pulse);
	ALPHA = COLOR.a;
}
