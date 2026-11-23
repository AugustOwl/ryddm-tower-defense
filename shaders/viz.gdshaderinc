// Ground visualizer patterns shared by level_pulse.gdshader (tiles, walls, bottom plane) and
// ground_layer.gdshader (the translucent layers under the board).
// viz_pattern() returns a glow amount (roughly 0..2) from the music's bass / mid / treble / texture.
//   type 0  Rings        rings travelling outward from the center of the board
//   type 1  Waves        straight fronts sweeping across the board
//   type 2  Cells        a patchwork of cells that swell and fade out of step with each other
//   type 3  Sparkle      tiny points of light that flicker with the treble
//   type 4  Off

float viz_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// A soft band that repeats every 1.0 of x: 1 at its center, fading smoothly to 0 on BOTH sides, so a ring swells,
// rolls outward and fades with no hard edge or restart. (A fract()-based ramp has a hard cut every cycle.)
float viz_band(float x) {
	return pow(0.5 + 0.5 * cos(6.2831853 * x), 8.0);
}

float viz_pattern(int type, vec3 p, float phase, float spacing, float bass, float mid, float treble, float tex, float time) {
	float drive = 0.25 + 1.1 * bass + 0.5 * mid;
	float warp = tex * 0.6 * sin(p.x * 0.8 + p.z * 1.1 + phase * 6.2831853);
	if (type == 0) {
		float d = length(p.xz);
		return viz_band((d + warp) / spacing - phase) * exp(-d * 0.035) * drive;
	} else if (type == 1) {
		float along = dot(p.xz, normalize(vec2(1.0, 0.6)));
		return viz_band((along + warp) / spacing - phase) * drive;
	} else if (type == 2) {
		vec2 cell = floor(p.xz / 1.7);
		float swell = 0.5 + 0.5 * sin(viz_hash(cell) * 6.2831853 + phase * 6.2831853);
		return pow(swell, 6.0) * drive;
	} else if (type == 3) {
		float flicker = viz_hash(floor(p.xz * 3.0) + floor(time * 10.0));
		return step(0.96 - treble * 0.12, flicker) * treble * 1.5;
	}
	return 0.0;
}
