uniform float u_time;
uniform vec2 u_resolution;
uniform vec2 u_cursor_pos;
uniform vec2 u_cell_size;
uniform float u_cursor_age;

vec4 effect(vec4 color, vec2 tex_coord, vec2 px_coord) {
    float pulse = sin(u_time * 15.0) * 0.5 + 0.5;
    float alpha = (1.0 - u_cursor_age) * (0.7 + pulse * 0.3);
    return vec4(1.0, 0.0, 1.0, alpha);
}
