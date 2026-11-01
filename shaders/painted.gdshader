shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Aspecto pintado a mano (como las referencias del moodboard): el color de cada cara
// se modula con pinceladas proyectadas en tres ejes. En paredes los trazos son
// verticales y en suelos horizontales, más un grano fino de pintura y algún
// desconchón más claro en los cantos.

uniform sampler2D brush : source_color, repeat_enable, filter_linear_mipmap;
uniform float scale = 0.6;
uniform float strength = 0.5;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	// Trazos alargados: estirados en vertical en las paredes
	float bx = texture(brush, wpos.zy * vec2(scale, scale * 0.28)).r;
	float bz = texture(brush, wpos.xy * vec2(scale, scale * 0.28) + 0.37).r;
	float by = texture(brush, wpos.xz * vec2(scale * 0.3, scale) + 0.71).r;
	float b = bx * w.x + by * w.y + bz * w.z;
	float fine = texture(brush, wpos.xz * 2.7 + wpos.y * 1.9).g;
	vec3 c = COLOR.rgb * (1.0 - strength * 0.5 + b * strength) * (0.95 + fine * 0.1);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
