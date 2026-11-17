shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
// Inverted-hull outline, used as the `next_pass` of an enemy's body material.
// Thickness and brightness follow the beat.

global uniform float beat_pulse;
global uniform float event_pulse;
global uniform vec4 beat_color;
global uniform float color_drain;   // drained to grey while deploying a tower

uniform float width = 0.03;
uniform float pulse_width = 0.07;

void vertex() {
	VERTEX += NORMAL * (width + pulse_width * beat_pulse);
}

void fragment() {
	float grey = dot(beat_color.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(beat_color.rgb, vec3(grey), color_drain) * (0.6 + 0.9 * beat_pulse + 0.6 * event_pulse);
}
