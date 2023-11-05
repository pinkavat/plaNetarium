shader_type spatial;
render_mode unshaded;

uniform float line_width = 4.0;

// All glory to https://mattdesl.svbtle.com/drawing-lines-is-hard
void vertex() {
	
	// Get the clip-space line segment ends
	vec4 a_proj = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 b_proj = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0));
	
	// Transform into NDC
	vec2 a_screen = a_proj.xy / a_proj.w;
	vec2 b_screen = b_proj.xy / b_proj.w;
	
	// Compute line normal
	vec2 screen_line = b_screen - a_screen;
	vec2 screen_normal = normalize(vec2(-screen_line.y, screen_line.x));
	
	// Adjust normal by screen aspect ratio
	screen_normal.x *= VIEWPORT_SIZE.y / VIEWPORT_SIZE.x;
	
	// Convert line width from pixels to NDC
	float width = line_width / VIEWPORT_SIZE.x;
	
	// Apply normal and tangential offsets
	vec2 screen_offset = a_screen + (screen_normal * UV.y * width);
	screen_offset += (screen_line * UV.x);
	
	// Retransform back to clip space
	// TODO: this doesn't *quite* work, but it stops the weird jumpies.
	//POSITION = vec4(screen_offset * a_proj.w, a_proj.zw);
	float fake_w = mix(a_proj.w, b_proj.w, UV.x);
	POSITION = vec4(screen_offset * fake_w, mix(a_proj.z, b_proj.z, UV.x), fake_w);
}

void fragment() {
	ALBEDO.rgb = COLOR.rgb;
	ALPHA = COLOR.a;
}
