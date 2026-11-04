extends Node3D
# Verdant Reach (Godot test): realistic island, sky, water, forest, explorer.

const R := 190.0          # island radius (m)
const SIZE := 420.0       # terrain square size (m)
const RES := 150          # terrain grid cells per side
const TREE_TRIES := 12000
const TREE_MAX := 1500
const ROCKS := 220
const GRASS_COUNT := 0      # black tufts removed (set e.g. 6000 to bring them back)
const DAY_LENGTH := 600.0 # seconds per full day

var noise: FastNoiseLite
var noise2: FastNoiseLite
var noise3: FastNoiseLite
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var player: CharacterBody3D
var water_mat: Material
var hud: Control
var time_of_day := 0.31

var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_id := -1
var run_toggle := false

var look := {}
var pal := {}
var menu_open := false
var gest_open := false
const CHAR_KEYS := ["boy", "girl", "male", "female"]
const CHAR_NAMES := ["Boy", "Girl", "Explorer M", "Explorer F"]
const LOOK_ROWS := [["tint", "Tint (Boy/Girl)"], ["skin", "Skin"], ["hair", "Hair"], ["top", "Top"], ["pants", "Pants"], ["boots", "Boots"], ["eyes", "Eyes"], ["scarf", "Scarf"], ["pack", "Backpack"]]


func _ready() -> void:
    noise = FastNoiseLite.new()
    noise.seed = 1337
    noise.frequency = 0.008
    noise.fractal_octaves = 4
    noise2 = FastNoiseLite.new()
    noise2.seed = 4242
    noise2.frequency = 0.02
    noise3 = FastNoiseLite.new()
    noise3.seed = 99
    noise3.frequency = 0.015

    _build_environment()
    _build_terrain()
    _build_water()
    _build_forest()
    # (flat tree picture wall removed)
    _build_assets()
    _build_meadow()
    _build_fauna()
    _make_palettes()
    _load_look()
    _build_player()
    apply_look()
    _build_map()
    _build_hud()
    _update_sky()
    _build_audio()
    player.set("step_cb", Callable(self, "_footstep"))
    _build_online_ui()


func height_at(x: float, z: float) -> float:
    var d := Vector2(x, z).length() / R
    var fall := clampf(1.0 - pow(d, 2.4), 0.0, 1.0)
    var n := noise.get_noise_2d(x, z)
    var m := noise2.get_noise_2d(x, z)
    return fall * (9.0 + n * 11.0 + absf(m) * 6.0) - 3.5 * (1.0 - fall)


func slope_at(x: float, z: float) -> float:
    var e := 1.5
    var dx := height_at(x + e, z) - height_at(x - e, z)
    var dz := height_at(x, z + e) - height_at(x, z - e)
    return Vector2(dx, dz).length() / (2.0 * e)


# ---------------------------------------------------------------- environment
func _build_environment() -> void:
    var sh := Shader.new()
    sh.code = SKY_CODE
    sky_mat = ShaderMaterial.new()
    sky_mat.shader = sh
    var sky := Sky.new()
    sky.sky_material = sky_mat
    sky.radiance_size = Sky.RADIANCE_SIZE_128
    env = Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.ambient_light_energy = 1.7
    env.ambient_light_sky_contribution = 1.0
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.glow_enabled = true
    env.glow_intensity = 0.35
    env.glow_bloom = 0.05
    env.fog_enabled = true
    env.fog_light_color = Color(0.62, 0.72, 0.82)
    env.fog_density = 0.0020
    env.fog_sky_affect = 0.4
    env.adjustment_enabled = true
    env.adjustment_contrast = 1.08
    env.adjustment_saturation = 1.12
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)

    sun = DirectionalLight3D.new()
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 110.0
    sun.light_color = Color(1.0, 0.96, 0.88)
    add_child(sun)


func _v3(c: Color) -> Vector3:
    var l := c.srgb_to_linear()
    return Vector3(l.r, l.g, l.b)


func _update_sky() -> void:
    var elev := sin((time_of_day - 0.25) * TAU) * 78.0
    sun.rotation_degrees = Vector3(-elev, 40.0, 0.0)
    var day := clampf(elev / 25.0 + 0.25, 0.0, 1.0)
    var dusk := clampf(1.0 - absf(elev) / 20.0, 0.0, 1.0)
    sun.light_energy = clampf(elev / 25.0, 0.0, 1.0) * 1.45
    sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.58, 0.3), dusk)
    sun.visible = elev > -2.0
    var top_day := Color(0.16, 0.36, 0.75)
    var hor_day := Color(0.62, 0.76, 0.90)
    var top_night := Color(0.01, 0.015, 0.05)
    var hor_night := Color(0.03, 0.04, 0.09)
    var hor := hor_night.lerp(hor_day, day).lerp(Color(0.95, 0.55, 0.35), dusk * 0.55)
    sky_mat.set_shader_parameter("top_color", _v3(top_night.lerp(top_day, day)))
    sky_mat.set_shader_parameter("hor_color", _v3(hor))
    sky_mat.set_shader_parameter("ground_color", _v3(Color(0.05, 0.07, 0.05).lerp(Color(0.18, 0.22, 0.16), day)))
    sky_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
    sky_mat.set_shader_parameter("day", day)
    sky_mat.set_shader_parameter("dusk", dusk)
    sky_mat.set_shader_parameter("sun_vis", 1.0 if elev > -3.0 else 0.0)
    env.background_energy_multiplier = 1.0
    env.ambient_light_energy = lerpf(0.25, 0.8, day)
    env.fog_light_color = Color(0.04, 0.05, 0.09).lerp(Color(0.60, 0.72, 0.84), day).lerp(Color(0.9, 0.6, 0.45), dusk * 0.4)


const SKY_CODE := """
shader_type sky;
uniform vec3 top_color = vec3(0.1, 0.3, 0.7);
uniform vec3 hor_color = vec3(0.6, 0.75, 0.9);
uniform vec3 ground_color = vec3(0.1, 0.15, 0.1);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float day = 1.0;
uniform float dusk = 0.0;
uniform float sun_vis = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.03;
        a *= 0.5;
    }
    return v;
}

void sky() {
    vec3 dir = EYEDIR;
    float h = dir.y;
    vec3 col;
    if (h > 0.0) {
        col = mix(hor_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
    } else {
        col = mix(hor_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
    }
    float sd = max(dot(dir, normalize(sun_dir)), 0.0);
    vec3 sun_col = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.55, 0.25), dusk);
    col += sun_col * (pow(sd, 900.0) * 10.0 + pow(sd, 16.0) * 0.30) * sun_vis;
    col += vec3(1.0, 0.45, 0.2) * pow(sd, 3.0) * dusk * 0.35 * sun_vis;
    if (h > 0.01) {
        vec2 uv = dir.xz / (h + 0.18) * 0.7 + vec2(TIME * 0.006, TIME * 0.002);
        float c = fbm(uv * 1.3);
        c = smoothstep(0.50, 0.82, c);
        float fade = smoothstep(0.01, 0.22, h);
        vec3 lit = mix(vec3(0.62, 0.66, 0.74), vec3(1.0, 0.98, 0.95), day);
        lit = mix(lit, vec3(1.0, 0.65, 0.45), dusk * 0.5);
        vec3 shade = lit * mix(0.45, 0.75, day);
        vec3 ccol = mix(shade, lit, smoothstep(0.5, 0.9, fbm(uv * 2.7 + 5.0)));
        ccol *= mix(0.12, 1.0, day);
        col = mix(col, ccol, c * fade * 0.9);
    }
    if (day < 0.5 && h > 0.0) {
        vec2 g = floor(dir.xz / (h + 0.3) * 140.0);
        float st = step(0.9975, hash(g));
        col += vec3(st) * (1.0 - day * 2.0) * smoothstep(0.0, 0.15, h);
    }
    COLOR = col;
}
"""


# ---------------------------------------------------------------- terrain
func _terrain_color(x: float, z: float, h: float, sl: float) -> Color:
    var grass_a := Color(0.20, 0.38, 0.12)
    var grass_b := Color(0.34, 0.46, 0.16)
    var sand := Color(0.78, 0.71, 0.52)
    var rock := Color(0.46, 0.43, 0.39)
    var mud := Color(0.28, 0.22, 0.14)
    var n := noise3.get_noise_2d(x, z) * 0.5 + 0.5
    var c := grass_a.lerp(grass_b, n)
    if h < 2.0:
        c = c.lerp(sand, clampf((2.0 - h) / 1.4, 0.0, 1.0))
    if h < -0.6:
        c = c.lerp(mud, clampf((-0.6 - h) / 1.5, 0.0, 0.8))
    c = c.lerp(rock, clampf((sl - 0.45) / 0.35, 0.0, 1.0))
    if h > 14.0:
        c = c.lerp(rock, clampf((h - 14.0) / 6.0, 0.0, 0.7))
    return c


func _build_terrain() -> void:
    var step := SIZE / float(RES)
    var verts := PackedVector3Array()
    var norms := PackedVector3Array()
    var cols := PackedColorArray()
    var uvs := PackedVector2Array()
    var idx := PackedInt32Array()
    var e := 0.8
    for j in RES + 1:
        for i in RES + 1:
            var x := -SIZE * 0.5 + i * step
            var z := -SIZE * 0.5 + j * step
            var h := height_at(x, z)
            var dx := height_at(x + e, z) - height_at(x - e, z)
            var dz := height_at(x, z + e) - height_at(x, z - e)
            var nrm := Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized()
            verts.append(Vector3(x, h, z))
            norms.append(nrm)
            cols.append(_terrain_color(x, z, h, Vector2(dx, dz).length() / (2.0 * e)))
            uvs.append(Vector2(x, z) * 0.1)
    for j in RES:
        for i in RES:
            var a := j * (RES + 1) + i
            var b := a + 1
            var c := a + (RES + 1)
            var d := c + 1
            idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = norms
    arrays[Mesh.ARRAY_COLOR] = cols
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = idx
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var tex_noise := FastNoiseLite.new()
    tex_noise.frequency = 0.04
    tex_noise.fractal_octaves = 5
    var tex := NoiseTexture2D.new()
    tex.noise = tex_noise
    tex.seamless = true
    tex.width = 512
    tex.height = 512
    var ramp := Gradient.new()
    ramp.set_color(0, Color(0.45, 0.45, 0.45))
    ramp.set_color(1, Color(1.0, 1.0, 1.0))
    tex.color_ramp = ramp
    var ntex := NoiseTexture2D.new()
    ntex.noise = tex_noise
    ntex.seamless = true
    ntex.as_normal_map = true
    ntex.bump_strength = 4.0
    ntex.width = 512
    ntex.height = 512

    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.vertex_color_is_srgb = true
    mat.albedo_texture = tex
    mat.normal_enabled = true
    mat.normal_texture = ntex
    mat.normal_scale = 0.8
    mat.uv1_triplanar = true
    mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
    mat.roughness = 0.95
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = _terrain_material(mat)
    add_child(mi)

    var body := StaticBody3D.new()
    var cs := CollisionShape3D.new()
    cs.shape = mesh.create_trimesh_shape()
    body.add_child(cs)
    add_child(body)


const WATER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, specular_schlick_ggx;
uniform sampler2D nmap : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float wave_amp = 1.0;
varying vec3 wpos;

void vertex() {
    vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float t = TIME;
    float a1 = w.x * 0.09 + t * 0.9;
    float a2 = w.z * 0.07 - t * 0.7 + 1.3;
    float a3 = (w.x + w.z) * 0.15 + t * 1.4;
    float a4 = (w.x * 0.6 - w.z) * 0.23 - t * 1.9;
    float h = sin(a1) * 0.35 + sin(a2) * 0.3 + sin(a3) * 0.15 + sin(a4) * 0.08;
    float dx = cos(a1) * 0.0315 + cos(a3) * 0.0225 + cos(a4) * 0.01104;
    float dz = cos(a2) * 0.021 + cos(a3) * 0.0225 - cos(a4) * 0.0184;
    VERTEX.y += h * 0.6 * wave_amp;
    NORMAL = normalize(vec3(-dx * 0.6 * wave_amp, 1.0, -dz * 0.6 * wave_amp));
    wpos = w;
}

void fragment() {
    vec2 uv1 = wpos.xz * 0.045 + vec2(TIME * 0.020, TIME * 0.014);
    vec2 uv2 = wpos.xz * 0.12 - vec2(TIME * 0.030, -TIME * 0.022);
    vec3 n1 = texture(nmap, uv1).xyz;
    vec3 n2 = texture(nmap, uv2).xyz;
    NORMAL_MAP = mix(n1, n2, 0.5);
    NORMAL_MAP_DEPTH = 0.9;

    float d = texture(depth_tex, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
    vec4 vw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    vw.xyz /= vw.w;
    float thick = max(-vw.z + VERTEX.z, 0.0);

    float deep = clamp(thick / 4.0, 0.0, 1.0);
    vec3 shallow_c = vec3(0.10, 0.42, 0.42);
    vec3 deep_c = vec3(0.01, 0.10, 0.20);
    vec3 col = mix(shallow_c, deep_c, deep);
    float lines = texture(nmap, wpos.xz * 0.2 + vec2(TIME * 0.05, 0.0)).z;
    float foam_band = smoothstep(0.9, 0.0, thick);
    float surge = 0.55 + 0.45 * sin(TIME * 1.6 + wpos.x * 0.25 + wpos.z * 0.2 - thick * 5.0);
    float foam = foam_band * surge * smoothstep(0.35, 0.8, lines + foam_band * 0.4);
    foam = clamp(foam + smoothstep(0.97, 1.0, n1.y) * 0.25, 0.0, 1.0);
    ALBEDO = mix(col, vec3(0.95), foam);
    ALPHA = clamp(mix(0.30, 0.93, deep) + foam, 0.0, 1.0);
    ROUGHNESS = mix(0.04, 0.5, foam);
    SPECULAR = 0.7;
}
"""


func _water_code() -> String:
    if not OS.has_feature("web"):
        return WATER_CODE
    # browser (compatibility renderer): no depth-texture foam
    var c := WATER_CODE.replace("uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;", "")
    var a := c.find("    float d = texture(depth_tex")
    var b := c.find("    float deep =")
    c = c.substr(0, a) + "    float thick = 2.5;\n\n" + c.substr(b)
    return c


func _build_water() -> void:
    var wn := FastNoiseLite.new()
    wn.frequency = 0.02
    wn.fractal_octaves = 3
    var nt := NoiseTexture2D.new()
    nt.noise = wn
    nt.seamless = true
    nt.as_normal_map = true
    nt.bump_strength = 6.0
    nt.width = 512
    nt.height = 512
    var sh := Shader.new()
    sh.code = _water_code()
    var inner := ShaderMaterial.new()
    inner.shader = sh
    inner.set_shader_parameter("nmap", nt)
    inner.set_shader_parameter("wave_amp", 1.0)
    water_mat = inner
    var outer := ShaderMaterial.new()
    outer.shader = sh
    outer.set_shader_parameter("nmap", nt)
    outer.set_shader_parameter("wave_amp", 0.0)
    # near the island: finely cut plane so the waves really move
    var pm := PlaneMesh.new()
    pm.size = Vector2(760, 760)
    var subd := 240 if not OS.has_feature("web") else 110
    pm.subdivide_width = subd
    pm.subdivide_depth = subd
    var mi := MeshInstance3D.new()
    mi.mesh = pm
    mi.material_override = inner
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.extra_cull_margin = 4.0
    add_child(mi)
    # far sea: flat and cheap
    var pf := PlaneMesh.new()
    pf.size = Vector2(3000, 3000)
    var mf := MeshInstance3D.new()
    mf.mesh = pf
    mf.material_override = outer
    mf.position = Vector3(0, -0.35, 0)
    mf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mf)


# ---------------------------------------------------------------- real textures (res://tex/)
func _tex(path: String) -> Texture2D:
    if ResourceLoader.exists(path):
        return load(path) as Texture2D
    if FileAccess.file_exists(path):
        var img := Image.load_from_file(path)
        if img != null and not img.is_empty():
            img.generate_mipmaps()
            return ImageTexture.create_from_image(img)
    return null


func _terrain_material(fallback: Material) -> Material:
    var gc := _tex("res://tex/grass_color.jpg")
    var rc := _tex("res://tex/rock_color.jpg")
    if gc == null or rc == null:
        print("Terrain textures not found in res://tex/ - using plain colors")
        return fallback
    var sh := Shader.new()
    sh.code = TERRAIN_CODE
    var m := ShaderMaterial.new()
    m.shader = sh
    m.set_shader_parameter("grass_alb", gc)
    m.set_shader_parameter("rock_alb", rc)
    var names := ["grass_nrm", "grass_rgh", "grass_ao", "rock_nrm", "rock_rgh", "rock_ao"]
    var files := ["grass_normal", "grass_rough", "grass_ao", "rock_normal", "rock_rough", "rock_ao"]
    for i in names.size():
        var t := _tex("res://tex/" + files[i] + ".jpg")
        if t != null:
            m.set_shader_parameter(names[i], t)
    return m


const TERRAIN_CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_scale = 0.22;
uniform float rock_scale = 0.13;
varying vec3 wpos;
varying vec3 wnrm;
varying vec3 vcol;

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    vcol = COLOR.rgb;
}

void fragment() {
    vec3 n = normalize(wnrm);
    float slope = 1.0 - n.y;

    vec2 gu = wpos.xz * grass_scale;
    vec2 gu2 = wpos.xz * grass_scale * 0.173 + vec2(0.37, 0.61);
    vec3 galb = mix(texture(grass_alb, gu).rgb, texture(grass_alb, gu2).rgb, 0.35);
    galb *= mix(vec3(1.0), vcol * 2.4, 0.22);
    float grgh = texture(grass_rgh, gu).r;
    float gao = texture(grass_ao, gu).r;
    vec3 gnm = texture(grass_nrm, gu).xyz * 2.0 - 1.0;

    vec3 tw = pow(abs(n), vec3(4.0));
    tw /= (tw.x + tw.y + tw.z + 0.0001);
    vec2 ux = wpos.zy * rock_scale;
    vec2 uy = wpos.xz * rock_scale;
    vec2 uz = wpos.xy * rock_scale;
    vec3 ralb = texture(rock_alb, ux).rgb * tw.x + texture(rock_alb, uy).rgb * tw.y + texture(rock_alb, uz).rgb * tw.z;
    float rrgh = texture(rock_rgh, ux).r * tw.x + texture(rock_rgh, uy).r * tw.y + texture(rock_rgh, uz).r * tw.z;
    float rao = texture(rock_ao, ux).r * tw.x + texture(rock_ao, uy).r * tw.y + texture(rock_ao, uz).r * tw.z;
    vec3 rnm = texture(rock_nrm, uy).xyz * 2.0 - 1.0;

    float rock_w = smoothstep(0.26, 0.5, slope);
    rock_w = max(rock_w, smoothstep(15.0, 22.0, wpos.y) * 0.6);
    float sand_w = smoothstep(2.7, 1.1, wpos.y);
    float mud_w = smoothstep(-0.2, -1.7, wpos.y);
    vec3 sand = vec3(0.52, 0.42, 0.26) * (0.75 + 0.5 * texture(grass_ao, gu * 1.7).r);

    vec3 alb = mix(galb, sand, sand_w * (1.0 - rock_w));
    alb = mix(alb, vec3(0.07, 0.055, 0.04), mud_w * (1.0 - rock_w));
    alb = mix(alb, ralb, rock_w);
    float ao = mix(gao, rao, rock_w);
    float rgh = mix(grgh, rrgh, rock_w);

    vec3 pn = mix(vec3(gnm.x, 0.0, -gnm.y), vec3(rnm.x, 0.0, -rnm.y), rock_w) * 0.9 * (1.0 - sand_w * 0.7);
    vec3 wn = normalize(n + pn);
    NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

    ALBEDO = alb * mix(1.0, ao, 0.65);
    ROUGHNESS = clamp(rgh * 0.5 + 0.55, 0.0, 1.0);
    SPECULAR = 0.25;
}
"""


func _build_treeline() -> void:
    var tex := _tex("res://tex/treeline.png")
    if tex == null:
        return
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = tex
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    mat.alpha_scissor_threshold = 0.5
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.roughness = 1.0
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    var quad := QuadMesh.new()
    quad.size = Vector2(150.0, 13.0)
    for k in 9:
        var a := k * TAU / 9.0 + 0.25
        var p := Vector3(cos(a), 0.0, sin(a)) * R * 0.74
        var h := height_at(p.x, p.z)
        if h < 1.2:
            continue
        var d := -p.normalized()
        var mi := MeshInstance3D.new()
        mi.mesh = quad
        mi.material_override = mat
        mi.position = Vector3(p.x, h + 5.2, p.z)
        mi.rotation.y = atan2(d.x, d.z)
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(mi)


# ---------------------------------------------------------------- 3D asset pack (res://assets/)
func _asset_mat() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.vertex_color_is_srgb = true
    m.roughness = 0.9
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m


func _scene_from(path: String) -> Node:
    if ResourceLoader.exists(path):
        var ps := load(path) as PackedScene
        if ps != null:
            return ps.instantiate()
    if FileAccess.file_exists(path):
        # not imported yet: read the .glb file directly
        var doc := GLTFDocument.new()
        var st := GLTFState.new()
        if doc.append_from_file(path, st) == OK:
            return doc.generate_scene(st)
    return null


# Loads a GLB, merges all its meshes into one mesh and turns it from Z-up to Y-up.
func _load_merged(path: String) -> ArrayMesh:
    var root := _scene_from(path)
    if root == null:
        return null
    var am := ArrayMesh.new()
    var stack: Array = [root]
    while stack.size() > 0:
        var n: Node = stack.pop_back()
        for c in n.get_children():
            stack.append(c)
        var mi := n as MeshInstance3D
        if mi == null or mi.mesh == null:
            continue
        for s in mi.mesh.get_surface_count():
            var arr := mi.mesh.surface_get_arrays(s)
            var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
            var nv := PackedVector3Array()
            nv.resize(v.size())
            for i in v.size():
                var p := mi.transform * v[i]
                nv[i] = Vector3(p.x, p.z, -p.y)
            arr[Mesh.ARRAY_VERTEX] = nv
            if arr[Mesh.ARRAY_NORMAL] != null:
                var no: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
                var nn := PackedVector3Array()
                nn.resize(no.size())
                for i in no.size():
                    nn[i] = Vector3(no[i].x, no[i].z, -no[i].y)
                arr[Mesh.ARRAY_NORMAL] = nn
            am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
    root.free()
    if am.get_surface_count() == 0:
        return null
    return am


func _scatter(mesh: Mesh, count: int, seed_v: int, hmin: float, hmax: float, smin: float, smax: float, max_slope: float, collide: bool, vis_end: float) -> void:
    if mesh == null:
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_v
    var xs: Array = []
    var body := StaticBody3D.new()
    var tries := 0
    while xs.size() < count and tries < count * 40:
        tries += 1
        var a := rng.randf() * TAU
        var r := sqrt(rng.randf()) * R * 0.92
        var x := cos(a) * r
        var z := sin(a) * r
        var h := height_at(x, z)
        if h < hmin or h > hmax or slope_at(x, z) > max_slope:
            continue
        if Vector2(x, z).length() < 5.0:
            continue
        var s := rng.randf_range(smin, smax)
        xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.05, z)))
        if collide:
            var cs := CollisionShape3D.new()
            var cyl := CylinderShape3D.new()
            cyl.radius = 0.25 * s
            cyl.height = 3.0
            cs.shape = cyl
            cs.position = Vector3(x, h + 1.5, z)
            body.add_child(cs)
    add_child(body)
    _make_mm(mesh, _asset_mat(), xs, [], true, vis_end)


func _place_solid(mesh: Mesh, pos: Vector3, yaw: float, sc: float, mat: Material = null) -> void:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat if mat != null else _asset_mat()
    mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), pos)
    add_child(mi)
    var body := StaticBody3D.new()
    body.transform = mi.transform
    var cs := CollisionShape3D.new()
    cs.shape = mesh.create_trimesh_shape()
    body.add_child(cs)
    add_child(body)


func _build_assets() -> void:

    # cabin on flat ground not far from where you start
    var cabin := _load_merged("res://assets/old_tropical_cabin.glb")
    if cabin != null:
        for k in 80:
            var a := k * 0.9
            var r := 14.0 + k * 1.1
            var x := cos(a) * r
            var z := sin(a) * r
            var h := height_at(x, z)
            var ok := h > 2.5 and slope_at(x, z) < 0.09
            for o in [Vector2(2.5, 2), Vector2(-2.5, 2), Vector2(2.5, -2), Vector2(-2.5, -2)]:
                var hh := height_at(x + o.x * 1.3, z + o.y * 1.3)
                if absf(hh - h) > 0.45:
                    ok = false
            if ok:
                _place_solid(cabin, Vector3(x, h - 0.05, z), a + PI * 0.5, 1.3, _bark_mat())
                map_marks.append({"p": Vector2(x, z), "t": "Cabin"})
                break

    # cave on a hillside, opening faces downhill
    var cave := _load_merged("res://assets/rocky_cave_entrance.glb")
    if cave != null:
        for k in 400:
            var a := k * 0.77
            var r := 20.0 + fmod(k * 7.3, R * 0.8)
            var x := cos(a) * r
            var z := sin(a) * r
            var h := height_at(x, z)
            var sl := slope_at(x, z)
            if h > 7.0 and sl > 0.25 and sl < 0.5:
                var gx := height_at(x + 1.5, z) - height_at(x - 1.5, z)
                var gz := height_at(x, z + 1.5) - height_at(x, z - 1.5)
                var d := Vector2(-gx, -gz).normalized()
                _place_solid(cave, Vector3(x, h - 0.4, z), atan2(-d.y, d.x), 2.6, _rock_mat())
                map_marks.append({"p": Vector2(x, z), "t": "Cave"})
                break


# ---------------------------------------------------------------- real meshes: grass, flowers, animals
# Loads a GLB and returns its first mesh with its own materials (textures stay).
func _load_mesh(path: String) -> Mesh:
    var root := _scene_from(path)
    if root == null:
        return null
    var found: Mesh = null
    var stack: Array = [root]
    while stack.size() > 0 and found == null:
        var n: Node = stack.pop_back()
        for c in n.get_children():
            stack.append(c)
        var mi := n as MeshInstance3D
        if mi != null and mi.mesh != null:
            found = mi.mesh
    root.free()
    return found


const ANIM_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_tex = true;
uniform bool scissor = false;
uniform float thr = 0.5;
uniform float rough = 0.85;
uniform float sway = 0.0;
uniform float height = 8.0;
uniform float flutter = 0.0;
uniform float legs = 0.0;
uniform float legspd = 3.0;
uniform float legmid = 0.0;
uniform float leglen = 0.8;
uniform float flap = 0.0;
uniform float flapspd = 6.0;
uniform float wag = 0.0;
uniform float wagspd = 7.0;

void vertex() {
    vec3 org = MODEL_MATRIX[3].xyz;
    float p0 = org.x * 1.7 + org.z * 2.3;
    if (sway > 0.0) {
        float h = clamp(VERTEX.y / height, 0.0, 1.0);
        h = h * h;
        float ph = TIME * 1.3 + org.x * 0.07 + org.z * 0.09;
        vec3 d = vec3(sin(ph) + 0.5 * sin(ph * 2.3 + 1.7), 0.0, cos(ph * 0.8 + 0.6) + 0.3) * sway * h;
        d += vec3(sin(TIME * 3.1 + dot(VERTEX, vec3(7.3, 11.1, 5.7))), sin(TIME * 2.7 + dot(VERTEX, vec3(3.1, 5.3, 9.7))), 0.0) * flutter * h;
        mat3 m = mat3(MODEL_MATRIX);
        float s2 = max(dot(m[0], m[0]), 0.0001);
        VERTEX += (transpose(m) * d) / s2;
    }
    if (legs > 0.0) {
        float side = ((VERTEX.x > 0.0) != (VERTEX.z > legmid)) ? 3.14159 : 0.0;
        float ph = TIME * legspd + side + p0;
        float w = clamp(1.0 - VERTEX.y / leglen, 0.0, 1.0);
        w = w * w;
        VERTEX.z += sin(ph) * legs * w;
        VERTEX.y += max(0.0, cos(ph)) * legs * 0.45 * w;
        VERTEX.y += abs(sin(TIME * legspd + p0)) * legs * 0.12;
    }
    if (flap > 0.0) {
        float a = abs(VERTEX.x);
        float amp = 0.6 + 0.4 * sin(TIME * 0.5 + p0);
        VERTEX.y += sin(TIME * flapspd + p0) * pow(a, 1.5) * flap * amp;
        VERTEX.y += sin(TIME * flapspd + p0 + 1.0) * 0.015;
    }
    if (wag > 0.0) {
        float a = abs(VERTEX.x) / 0.1;
        VERTEX.z += sin(TIME * wagspd + VERTEX.x * 22.0 + p0) * wag * (0.25 + 0.75 * a);
    }
}

void fragment() {
    vec4 c = tint;
    if (has_tex) {
        c *= texture(albedo_tex, UV);
    }
    if (scissor && c.a < thr) {
        discard;
    }
    ALBEDO = c.rgb;
    ROUGHNESS = rough;
}
"""
var _anim_shader: Shader = null


# Wraps a mesh's materials in a shader that moves vertices (wind, legs, wings, tail).
func _anim_mesh(mesh: Mesh, kind: String) -> Mesh:
    if mesh == null:
        return null
    if _anim_shader == null:
        _anim_shader = Shader.new()
        _anim_shader.code = ANIM_SHADER
    var hgt := maxf(mesh.get_aabb().size.y, 0.05)
    for i in mesh.get_surface_count():
        var src := mesh.surface_get_material(i) as StandardMaterial3D
        var sm := ShaderMaterial.new()
        sm.shader = _anim_shader
        if src != null:
            if src.albedo_texture != null:
                sm.set_shader_parameter("albedo_tex", src.albedo_texture)
                sm.set_shader_parameter("has_tex", true)
            else:
                sm.set_shader_parameter("has_tex", false)
            sm.set_shader_parameter("tint", src.albedo_color)
            sm.set_shader_parameter("scissor", src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
            sm.set_shader_parameter("thr", maxf(src.alpha_scissor_threshold, 0.3))
        else:
            sm.set_shader_parameter("has_tex", false)
        sm.set_shader_parameter("height", hgt)
        match kind:
            "tree":
                sm.set_shader_parameter("sway", hgt * 0.03)
                sm.set_shader_parameter("flutter", hgt * 0.006)
            "grass":
                sm.set_shader_parameter("sway", hgt * 0.22)
                sm.set_shader_parameter("flutter", hgt * 0.02)
            "bull":
                sm.set_shader_parameter("legs", 0.2)
                sm.set_shader_parameter("legspd", 3.2)
                sm.set_shader_parameter("legmid", -0.35)
                sm.set_shader_parameter("leglen", 0.85)
            "skunk":
                sm.set_shader_parameter("legs", 0.03)
                sm.set_shader_parameter("legspd", 9.0)
                sm.set_shader_parameter("legmid", -0.07)
                sm.set_shader_parameter("leglen", 0.1)
            "egret":
                sm.set_shader_parameter("flap", 0.9)
                sm.set_shader_parameter("flapspd", 5.5)
            "carp":
                sm.set_shader_parameter("wag", 0.012)
                sm.set_shader_parameter("wagspd", 7.0)
        mesh.surface_set_material(i, sm)
    return mesh


func _build_meadow() -> void:
    var defs := [
        ["grass_a", 14, 1.5, 2.4], ["grass_b", 14, 1.4, 2.3], ["grass_c", 8, 1.4, 2.2],
        ["grass_tiny", 20, 1.6, 2.6], ["flower_daisy", 4, 1.6, 2.4], ["flower_dandelion", 6, 2.0, 3.0],
        ["clover", 8, 1.6, 2.4]]
    var rng := RandomNumberGenerator.new()
    rng.seed = 90210
    var cs := 40.0
    var cn := int(ceil(SIZE / cs))
    for d in defs:
        var mesh := _anim_mesh(_load_mesh("res://assets/%s.glb" % d[0]), "grass")
        if mesh == null:
            continue
        for cx in cn:
            for cz in cn:
                var xs: Array = []
                var ox := -SIZE * 0.5 + cx * cs
                var oz := -SIZE * 0.5 + cz * cs
                if Vector2(ox + cs * 0.5, oz + cs * 0.5).length() > R * 1.0:
                    continue
                for k in (int(d[1]) if not OS.has_feature("web") else int(d[1]) / 2):
                    var x := ox + rng.randf() * cs
                    var z := oz + rng.randf() * cs
                    var h := height_at(x, z)
                    if h < 1.9 or h > 16.0 or slope_at(x, z) > 0.45:
                        continue
                    if noise3.get_noise_2d(x * 2.1, z * 2.1) < -0.3:
                        continue
                    var s := rng.randf_range(float(d[2]), float(d[3]))
                    xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.03, z)))
                _make_mm(mesh, null, xs, [], false, 62.0)


var fauna: Array = []     # {node, kind, c, r, spd, ph, y}


func _spot(rng: RandomNumberGenerator, hmin: float, hmax: float, max_slope: float) -> Vector3:
    for t in 300:
        var a := rng.randf() * TAU
        var r := sqrt(rng.randf()) * R * 0.9
        var x := cos(a) * r
        var z := sin(a) * r
        var h := height_at(x, z)
        if h >= hmin and h <= hmax and slope_at(x, z) <= max_slope and Vector2(x, z).length() > 8.0:
            return Vector3(x, h, z)
    return Vector3(INF, 0, 0)


func _add_fauna(mesh: Mesh, pos: Vector3, yaw: float, sc: float) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), pos)
    mi.visibility_range_end = 240.0
    add_child(mi)
    return mi


func _build_fauna() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 5150
    var bull := _anim_mesh(_load_mesh("res://assets/animal_bull.glb"), "bull")
    if bull != null:
        for i in 5:
            var p := _spot(rng, 3.0, 14.0, 0.1)
            if p.x == INF:
                continue
            var mi := _add_fauna(bull, p, rng.randf() * TAU, rng.randf_range(0.95, 1.1))
            var body := StaticBody3D.new()
            var cs := CollisionShape3D.new()
            var bx := BoxShape3D.new()
            bx.size = Vector3(0.9, 1.6, 2.5)
            cs.shape = bx
            cs.position = Vector3(0, 0.8, 0)
            body.add_child(cs)
            mi.add_child(body)
            fauna.append({"node": mi, "kind": "walk", "c": Vector2(p.x, p.z), "r": rng.randf_range(3.0, 5.0),
                "spd": rng.randf_range(0.09, 0.14) * (1.0 if i % 2 == 0 else -1.0), "ph": rng.randf() * TAU, "y": 0.0, "off": 0.0})
    var skunk := _anim_mesh(_load_mesh("res://assets/animal_skunk.glb"), "skunk")
    if skunk != null:
        for i in 6:
            var p := _spot(rng, 2.5, 12.0, 0.3)
            if p.x != INF:
                var mi := _add_fauna(skunk, p, 0.0, rng.randf_range(0.9, 1.2))
                fauna.append({"node": mi, "kind": "walk", "c": Vector2(p.x, p.z), "r": rng.randf_range(1.5, 3.0),
                    "spd": rng.randf_range(0.15, 0.25) * (1.0 if i % 2 == 0 else -1.0), "ph": rng.randf() * TAU, "y": 0.0, "off": 0.0})
    var egret := _anim_mesh(_load_mesh("res://assets/animal_egret.glb"), "egret")
    if egret != null:
        for i in 5:
            var mi := _add_fauna(egret, Vector3.ZERO, 0.0, 2.2)
            mi.visibility_range_end = 0.0
            fauna.append({"node": mi, "kind": "bird", "c": Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80)),
                "r": rng.randf_range(30.0, 90.0), "spd": rng.randf_range(0.05, 0.1) * (1.0 if i % 2 == 0 else -1.0),
                "ph": rng.randf() * TAU, "y": rng.randf_range(28.0, 48.0), "off": 0.0})
    var carp := _anim_mesh(_load_mesh("res://assets/animal_carp.glb"), "carp")
    if carp != null:
        for i in 16:
            var p := _spot(rng, -4.0, -1.0, 0.5)
            if p.x == INF:
                continue
            var mi := _add_fauna(carp, p, 0.0, 3.0)
            mi.visibility_range_end = 120.0
            fauna.append({"node": mi, "kind": "fish", "c": Vector2(p.x, p.z), "r": rng.randf_range(2.0, 5.0),
                "spd": rng.randf_range(0.25, 0.5) * (1.0 if i % 2 == 0 else -1.0), "ph": rng.randf() * TAU, "y": -0.35 - rng.randf() * 0.3, "off": -PI * 0.5})


func _update_fauna() -> void:
    var t := Time.get_ticks_msec() * 0.001
    for f in fauna:
        var mi: MeshInstance3D = f["node"]
        var ph: float = f["ph"] + t * float(f["spd"])
        var c: Vector2 = f["c"]
        var r: float = f["r"]
        var p := Vector3(c.x + cos(ph) * r, f["y"], c.y + sin(ph) * r)
        if f["kind"] == "bird":
            p.y += sin(t * 0.4 + ph * 2.0) * 2.0
        var dirv := Vector3(-sin(ph), 0.0, cos(ph)) * (1.0 if float(f["spd"]) > 0.0 else -1.0)
        var yaw := atan2(dirv.x, dirv.z) + float(f["off"])
        if f["kind"] == "walk":
            p.y = height_at(p.x, p.z) - 0.03
        var bank := 0.0
        if f["kind"] == "bird":
            bank = -0.25 * (1.0 if float(f["spd"]) > 0.0 else -1.0)
        mi.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), bank) * Basis.from_scale(mi.scale), p)


# ---------------------------------------------------------------- forest
func _make_mm(mesh: Mesh, mat: Material, xforms: Array, colors: Array, shadows: bool, vis_end: float) -> void:
    if xforms.is_empty():
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = colors.size() > 0
    mm.mesh = mesh
    mm.instance_count = xforms.size()
    for i in xforms.size():
        mm.set_instance_transform(i, xforms[i])
        if colors.size() > 0:
            mm.set_instance_color(i, (colors[i] as Color).srgb_to_linear())
    var mi := MultiMeshInstance3D.new()
    mi.multimesh = mm
    mi.material_override = mat
    if not shadows:
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if vis_end > 0.0:
        mi.visibility_range_end = vis_end
    add_child(mi)


func _bark_mat() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    var c := _tex("res://tex/bark_color.jpg")
    if c != null:
        m.albedo_texture = c
    m.albedo_color = Color(0.85, 0.7, 0.55)
    m.uv1_triplanar = true
    m.uv1_scale = Vector3(0.45, 0.45, 0.45)
    m.roughness = 0.9
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    var n := _tex("res://tex/bark_normal.jpg")
    if n != null:
        m.normal_enabled = true
        m.normal_texture = n
    m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return m


func _rock_mat() -> StandardMaterial3D:
    var rc := _tex("res://tex/rock_color.jpg")
    if rc == null:
        return _vc_mat(0.95)
    var m := StandardMaterial3D.new()
    m.albedo_texture = rc
    m.uv1_triplanar = true
    m.uv1_scale = Vector3(0.35, 0.35, 0.35)
    m.roughness = 0.95
    var rn := _tex("res://tex/rock_normal.jpg")
    if rn != null:
        m.normal_enabled = true
        m.normal_texture = rn
        m.normal_scale = 0.8
    var ra := _tex("res://tex/rock_ao.jpg")
    if ra != null:
        m.ao_enabled = true
        m.ao_texture = ra
    m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return m


func _vc_mat(rough: float = 0.9) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.roughness = rough
    return m


func _lumpy_rock() -> ArrayMesh:
    var sm := SphereMesh.new()
    sm.radius = 1.0
    sm.height = 1.4
    sm.radial_segments = 18
    sm.rings = 10
    var arr := sm.get_mesh_arrays()
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var nz := FastNoiseLite.new()
    nz.seed = 31
    nz.frequency = 1.3
    nz.fractal_octaves = 3
    var nv := PackedVector3Array()
    nv.resize(v.size())
    var nn := PackedVector3Array()
    nn.resize(v.size())
    for i in v.size():
        var p := v[i]
        var k := 1.0 + nz.get_noise_3d(p.x * 2.0, p.y * 2.0, p.z * 2.0) * 0.55
        k *= 1.0 + 0.12 * nz.get_noise_3d(p.x * 9.0, p.y * 9.0, p.z * 9.0)
        nv[i] = p * k
        nn[i] = Vector3(p.x, p.y / 0.7, p.z).normalized()
    arr[Mesh.ARRAY_VERTEX] = nv
    arr[Mesh.ARRAY_NORMAL] = nn
    var am := ArrayMesh.new()
    am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
    return am


func _build_forest() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20260311

    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.12
    trunk_mesh.bottom_radius = 0.22
    trunk_mesh.height = 1.0
    trunk_mesh.radial_segments = 7
    var pine_mesh := CylinderMesh.new()
    pine_mesh.top_radius = 0.0
    pine_mesh.bottom_radius = 1.5
    pine_mesh.height = 1.0
    pine_mesh.radial_segments = 9
    var broad_mesh := SphereMesh.new()
    broad_mesh.radius = 1.0
    broad_mesh.height = 1.7
    broad_mesh.radial_segments = 9
    broad_mesh.rings = 5
    var bl_mesh := _load_merged("res://assets/tropical_broadleaf_tree.glb")
    var bl_x: Array = []
    var maple: Array = []
    for nm in ["green", "green2", "gold", "red"]:
        var mm_ := _anim_mesh(_load_mesh("res://assets/tree_maple_%s.glb" % nm), "tree")
        if mm_ != null:
            maple.append(mm_)
    var cyp: Array = []
    for nm in ["a", "b"]:
        var cm_ := _anim_mesh(_load_mesh("res://assets/tree_cypress_%s.glb" % nm), "tree")
        if cm_ != null:
            cyp.append(cm_)
    var cells := {}
    var rock_mesh := _lumpy_rock()

    var trunk_x: Array = []
    var trunk_c: Array = []
    var pine_x: Array = []
    var pine_c: Array = []
    var broad_x: Array = []
    var broad_c: Array = []
    var tree_body := StaticBody3D.new()
    var count := 0
    for n in TREE_TRIES:
        if count >= (TREE_MAX if not OS.has_feature("web") else 700):
            break
        var a := rng.randf() * TAU
        var r := sqrt(rng.randf()) * R * 0.92
        var x := cos(a) * r
        var z := sin(a) * r
        var h := height_at(x, z)
        if h < 1.4 or slope_at(x, z) > 0.55:
            continue
        if noise3.get_noise_2d(x * 1.7, z * 1.7) < -0.25:
            continue
        if Vector2(x, z).length() < 6.0:
            continue
        var s := 0.8 + rng.randf() * 0.7
        var yaw := rng.randf() * TAU
        var pine := (h > 8.0) or noise2.get_noise_2d(x, z) > 0.1
        var th := 2.4 * s
        var tb := Basis(Vector3.UP, yaw).scaled(Vector3(s, th, s))
        var real_tree := (pine and cyp.size() > 0) or ((not pine) and maple.size() > 0)
        if not real_tree and (pine or bl_mesh == null):
            trunk_x.append(Transform3D(tb, Vector3(x, h + th * 0.5 - 0.1, z)))
            trunk_c.append(Color(0.30, 0.20, 0.12).lerp(Color(0.40, 0.30, 0.2), rng.randf()))
        if real_tree:
            var key := Vector3i(0, floori((x + R) / 105.0), floori((z + R) / 105.0))
            var sc := s
            if pine:
                key.x = 10 + rng.randi() % cyp.size()
                sc = s * 0.95
            else:
                var rv := rng.randf()
                var vi := 0 if rv < 0.4 else (1 if rv < 0.7 else (2 if rv < 0.88 else 3))
                key.x = mini(vi, maple.size() - 1)
            if not cells.has(key):
                cells[key] = []
            cells[key].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(x, h - 0.1, z)))
            # a young tree next to it (textured undergrowth instead of plain bushes)
            if rng.randf() < 0.35:
                var ba := rng.randf() * TAU
                var bd := rng.randf_range(2.5, 6.0)
                var bx := x + cos(ba) * bd
                var bz := z + sin(ba) * bd
                var bh := height_at(bx, bz)
                if bh > 1.6 and slope_at(bx, bz) < 0.5:
                    cells[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.3, 0.55)), Vector3(bx, bh - 0.05, bz)))
        elif pine:
            var ph := 6.0 * s
            var tiers := [1.0, 0.74, 0.5]
            for ti in 3:
                var ch := ph * 0.46
                var rs: float = tiers[ti]
                var pb := Basis(Vector3.UP, yaw + ti * 0.9).scaled(Vector3(s * rs, ch, s * rs))
                pine_x.append(Transform3D(pb, Vector3(x, h + th * 0.5 + ti * ph * 0.27 + ch * 0.5, z)))
                pine_c.append(Color(0.06, 0.20, 0.10).lerp(Color(0.13, 0.33, 0.15), rng.randf() * 0.6 + ti * 0.12))
        elif bl_mesh != null:
            bl_x.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s * 1.3), Vector3(x, h - 0.1, z)))
        else:
            var bs := 2.0 * s
            var g1 := Color(0.20, 0.40, 0.12)
            var g2 := Color(0.45, 0.45, 0.14)
            var g3 := Color(0.60, 0.30, 0.08)
            var base_c := g1.lerp(g2, rng.randf())
            if rng.randf() < 0.15:
                base_c = g1.lerp(g3, rng.randf())
            for bi in 4:
                var off := Vector3.ZERO
                var bsz := bs
                if bi > 0:
                    var ba := yaw + bi * 2.1
                    off = Vector3(cos(ba) * bs * 0.75, bs * (0.1 + 0.15 * bi), sin(ba) * bs * 0.75)
                    bsz = bs * 0.62
                var bb := Basis(Vector3.UP, yaw + bi).scaled(Vector3(bsz, bsz * 0.82, bsz))
                broad_x.append(Transform3D(bb, Vector3(x, h + th + bs * 0.55, z) + off))
                broad_c.append(base_c.lerp(Color(0.12, 0.30, 0.08), rng.randf() * 0.35).lightened(rng.randf() * 0.08))
        var cs := CollisionShape3D.new()
        var cyl := CylinderShape3D.new()
        cyl.radius = 0.3 * s
        cyl.height = 3.0
        cs.shape = cyl
        cs.position = Vector3(x, h + 1.5, z)
        tree_body.add_child(cs)
        count += 1
    add_child(tree_body)
    for key in cells.keys():
        var tmesh: Mesh = maple[key.x] if key.x < 10 else cyp[key.x - 10]
        _make_mm(tmesh, null, cells[key], [], true, 260.0)
    if bl_mesh != null:
        _make_mm(bl_mesh, _asset_mat(), bl_x, [], true, 0.0)
    var tm := _vc_mat(0.95)
    _make_mm(trunk_mesh, tm, trunk_x, trunk_c, true, 0.0)
    _make_mm(pine_mesh, _vc_mat(0.9), pine_x, pine_c, true, 0.0)
    _make_mm(broad_mesh, _vc_mat(0.85), broad_x, broad_c, true, 0.0)

    # rocks
    var rock_x: Array = []
    var rock_c: Array = []
    var rock_body := StaticBody3D.new()
    var rc := 0
    for n in 2000:
        if rc >= ROCKS:
            break
        var a := rng.randf() * TAU
        var r := sqrt(rng.randf()) * R * 0.98
        var x := cos(a) * r
        var z := sin(a) * r
        var h := height_at(x, z)
        if h < -1.5:
            continue
        var s := 0.3 + rng.randf() * rng.randf() * 1.6
        var b := Basis.from_euler(Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4)).scaled(Vector3(s * 1.2, s * 0.7, s))
        rock_x.append(Transform3D(b, Vector3(x, h + s * 0.15, z)))
        var g := 0.36 + rng.randf() * 0.18
        rock_c.append(Color(g, g * 0.96, g * 0.9))
        if s > 0.7:
            var cs := CollisionShape3D.new()
            var sh := SphereShape3D.new()
            sh.radius = s * 0.8
            cs.shape = sh
            cs.position = Vector3(x, h + s * 0.15, z)
            rock_body.add_child(cs)
        rc += 1
    add_child(rock_body)
    _make_mm(rock_mesh, _rock_mat(), rock_x, [], true, 0.0)

    # grass tufts: three crossed blades
    var gm := ArrayMesh.new()
    var gv := PackedVector3Array()
    var gc := PackedColorArray()
    var gn := PackedVector3Array()
    for k in 3:
        var ang := k * PI / 3.0
        var ox := cos(ang) * 0.12
        var oz := sin(ang) * 0.12
        gv.append_array(PackedVector3Array([Vector3(-ox, 0, -oz), Vector3(ox, 0, oz), Vector3(0, 0.55, 0)]))
        gc.append_array(PackedColorArray([Color(0.35, 0.35, 0.35), Color(0.35, 0.35, 0.35), Color(1, 1, 1)]))
        gn.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]))
    var garr := []
    garr.resize(Mesh.ARRAY_MAX)
    garr[Mesh.ARRAY_VERTEX] = gv
    garr[Mesh.ARRAY_COLOR] = gc
    garr[Mesh.ARRAY_NORMAL] = gn
    gm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, garr)
    var grass_x: Array = []
    var grass_c: Array = []
    var gcount := 0
    for n in GRASS_COUNT * 4:
        if gcount >= GRASS_COUNT:
            break
        var a := rng.randf() * TAU
        var r := sqrt(rng.randf()) * R * 0.85
        var x := cos(a) * r
        var z := sin(a) * r
        var h := height_at(x, z)
        if h < 1.8 or slope_at(x, z) > 0.6:
            continue
        var s := 0.45 + rng.randf() * 0.5
        var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
        grass_x.append(Transform3D(b, Vector3(x, h - 0.02, z)))
        grass_c.append(Color(0.16, 0.32, 0.08).lerp(Color(0.38, 0.46, 0.14), rng.randf()))
        gcount += 1
    var gmat := _vc_mat(1.0)
    gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
    _make_mm(gm, gmat, grass_x, grass_c, false, 110.0)


# ---------------------------------------------------------------- player + HUD
func _build_player() -> void:
    player = Player.new()
    add_child(player)
    var best := Vector2.ZERO
    var best_h := -99.0
    for k in 60:
        var a := k * 0.7
        var r := 4.0 + k * 1.2
        var p := Vector2(cos(a), sin(a)) * r
        var h := height_at(p.x, p.y)
        if h > 2.5 and slope_at(p.x, p.y) < 0.25:
            best = p
            best_h = h
            break
    if best_h < 0.0:
        best = Vector2(0, 0)
        best_h = maxf(height_at(0, 0), 1.0)
    player.position = Vector3(best.x, best_h + 1.5, best.y)


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Hud.new()
    hud.main = self
    hud.set_anchors_preset(Control.PRESET_FULL_RECT)
    hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(hud)


func jump_center() -> Vector2:
    var s := get_viewport().get_visible_rect().size
    return Vector2(s.x - 110.0, s.y - 110.0)


func run_center() -> Vector2:
    var s := get_viewport().get_visible_rect().size
    return Vector2(s.x - 250.0, s.y - 85.0)


func gest_center() -> Vector2:
    var s := get_viewport().get_visible_rect().size
    return Vector2(s.x - 110.0, s.y - 235.0)


func gest_items() -> Array:
    var out: Array = []
    var s := get_viewport().get_visible_rect().size
    var u := ui_scale()
    var cols := 5
    var w := 150.0 * u
    var h := 50.0 * u
    var gap := 8.0 * u
    var n: int = Player.GEST.size() - 1
    var rows := int(ceil(float(n) / float(cols)))
    var pw := cols * (w + gap) + gap
    var ph := rows * (h + gap) + gap + 56.0 * u
    var x0 := (s.x - pw) * 0.5
    var y0 := maxf(10.0, (s.y - ph) * 0.5) + 56.0 * u
    for i in n:
        var r := i / cols
        var c := i % cols
        out.append({"rect": Rect2(x0 + gap + c * (w + gap), y0 + gap + r * (h + gap), w, h), "id": i + 1, "text": Player.GEST[i + 1][0]})
    out.append({"rect": Rect2(x0 + pw - 130.0 * u - gap, y0 - 52.0 * u, 130.0 * u, 44.0 * u), "id": -1, "text": "CLOSE"})
    out.append({"rect": Rect2(x0, y0 - 56.0 * u, pw, ph), "id": -2, "text": ""})
    return out


func _gest_tap(p: Vector2) -> void:
    for it in gest_items():
        if int(it["id"]) == -2:
            continue
        if (it["rect"] as Rect2).has_point(p):
            if int(it["id"]) > 0:
                player.call("play_gesture", int(it["id"]))
            gest_open = false
            return
    gest_open = false


func _input(event: InputEvent) -> void:
    var size := get_viewport().get_visible_rect().size
    if online_open:
        return
    if event is InputEventScreenTouch and _over_ui((event as InputEventScreenTouch).position):
        return
    if gest_open:
        if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
            _gest_tap((event as InputEventScreenTouch).position)
        return
    if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
        var kc := (event as InputEventKey).keycode
        if kc == KEY_G:
            gest_open = true
            return
        if kc >= KEY_1 and kc <= KEY_9:
            player.call("play_gesture", int(kc - KEY_1) + 1)
            return
    if menu_open:
        if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
            _menu_tap((event as InputEventScreenTouch).position)
        return
    if map_open:
        if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
            map_open = false
        return
    if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
        if mini_rect().has_point((event as InputEventScreenTouch).position):
            map_open = true
            stick_id = -1
            stick_vec = Vector2.ZERO
            look_id = -1
            return
        if style_rect().has_point((event as InputEventScreenTouch).position):
            menu_open = true
            stick_id = -1
            stick_vec = Vector2.ZERO
            look_id = -1
            return
    if event is InputEventScreenTouch:
        var te := event as InputEventScreenTouch
        if te.pressed:
            if te.position.distance_to(jump_center()) < 70.0:
                player.call("jump")
            elif te.position.distance_to(gest_center()) < 52.0:
                gest_open = true
                stick_id = -1
                stick_vec = Vector2.ZERO
                look_id = -1
            elif te.position.distance_to(run_center()) < 55.0:
                run_toggle = not run_toggle
            elif te.position.x < size.x * 0.45 and stick_id == -1:
                stick_id = te.index
                stick_origin = te.position
                stick_vec = Vector2.ZERO
            elif look_id == -1:
                look_id = te.index
        else:
            if te.index == stick_id:
                stick_id = -1
                stick_vec = Vector2.ZERO
            if te.index == look_id:
                look_id = -1
    elif event is InputEventScreenDrag:
        var de := event as InputEventScreenDrag
        if de.index == stick_id:
            stick_vec = ((de.position - stick_origin) / 90.0).limit_length(1.0)
        elif de.index == look_id:
            player.set("cam_yaw", float(player.get("cam_yaw")) - de.relative.x * 0.006)
            player.set("cam_pitch", clampf(float(player.get("cam_pitch")) - de.relative.y * 0.005, -1.2, 0.5))


func _process(delta: float) -> void:
    time_of_day = fposmod(time_of_day + delta / DAY_LENGTH, 1.0)
    _update_sky()
    _update_fauna()
    _update_audio(delta)
    _net_process(delta)
    player.set("move_input", stick_vec)
    player.set("want_run", run_toggle or stick_vec.length() > 0.88)
    if hud != null:
        hud.queue_redraw()


# ---------------------------------------------------------------- sound + floating leaves (all made in code)
var snd_wind: AudioStreamPlayer
var snd_water: AudioStreamPlayer
var snd_night: AudioStreamPlayer
var steps_grass: Array = []
var steps_hard: Array = []
var steps_splash: Array = []
var chirps: Array = []
var step_player: AudioStreamPlayer
var bird_timer := 2.0
var pollen: GPUParticles3D
var leaves: GPUParticles3D
var _arng := RandomNumberGenerator.new()


func _wav(data: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
    var bytes := PackedByteArray()
    bytes.resize(data.size() * 2)
    for i in data.size():
        bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
    var w := AudioStreamWAV.new()
    w.format = AudioStreamWAV.FORMAT_16_BITS
    w.mix_rate = rate
    w.stereo = false
    w.data = bytes
    if loop:
        w.loop_mode = AudioStreamWAV.LOOP_FORWARD
        w.loop_begin = 0
        w.loop_end = data.size()
    return w


# looping filtered noise; lp = low-pass strength (0..1, higher = darker), hp = remove low rumble
func _noise_loop(secs: float, lp: float, hp: float, wobble: float) -> AudioStreamWAV:
    var rate := 22050
    var n := int(secs * rate)
    var d := PackedFloat32Array()
    d.resize(n)
    var a := 0.0
    var b := 0.0
    for i in n:
        var x := _arng.randf() * 2.0 - 1.0
        a = a * lp + x * (1.0 - lp)
        b = b * hp + a * (1.0 - hp)
        var v := (a - b) * (1.0 + wobble * sin(float(i) / rate * TAU * 0.35))
        d[i] = v
    # make the loop seamless: fade the last 0.5 s into the first 0.5 s
    var f := int(0.5 * rate)
    for i in f:
        var k := float(i) / f
        d[i] = d[i] * k + d[n - f + i] * (1.0 - k)
    d.resize(n - f)
    var peak := 0.001
    for v in d:
        peak = maxf(peak, absf(v))
    for i in d.size():
        d[i] = d[i] / peak * 0.8
    return _wav(d, rate, true)


func _burst(len_s: float, lp: float, hp: float, decay: float, gain: float) -> AudioStreamWAV:
    var rate := 22050
    var n := int(len_s * rate)
    var d := PackedFloat32Array()
    d.resize(n)
    var a := 0.0
    var b := 0.0
    for i in n:
        var x := _arng.randf() * 2.0 - 1.0
        a = a * lp + x * (1.0 - lp)
        b = b * hp + a * (1.0 - hp)
        var env_ := exp(-float(i) / n * decay) * minf(1.0, float(i) / 90.0)
        d[i] = (a - b) * env_ * gain
    return _wav(d, rate, false)


func _chirp(f0: float, f1: float, len_s: float, trills: int) -> AudioStreamWAV:
    var rate := 22050
    var n := int(len_s * rate)
    var d := PackedFloat32Array()
    d.resize(n)
    var ph := 0.0
    for i in n:
        var t := float(i) / n
        var f := lerpf(f0, f1, t) * (1.0 + 0.06 * sin(t * TAU * trills))
        ph += f / rate * TAU
        var env_ := sin(t * PI)
        env_ = env_ * env_
        d[i] = (sin(ph) + 0.3 * sin(ph * 2.0)) * env_ * 0.5
    return _wav(d, rate, false)


func _cricket_loop() -> AudioStreamWAV:
    var rate := 22050
    var n := rate * 2
    var d := PackedFloat32Array()
    d.resize(n)
    for i in n:
        var t := float(i) / rate
        var pulse := maxf(0.0, sin(t * TAU * 12.0)) * (0.5 + 0.5 * sin(t * TAU * 1.0 + 1.0))
        pulse = pulse * pulse
        d[i] = sin(t * TAU * 4200.0) * pulse * 0.3
    return _wav(d, rate, true)


func _build_audio() -> void:
    _arng.seed = 777
    snd_wind = AudioStreamPlayer.new()
    snd_wind.stream = _noise_loop(5.0, 0.93, 0.995, 0.5)
    snd_wind.volume_db = -14.0
    add_child(snd_wind)
    snd_wind.play()
    snd_water = AudioStreamPlayer.new()
    snd_water.stream = _noise_loop(4.0, 0.72, 0.97, 0.25)
    snd_water.volume_db = -80.0
    add_child(snd_water)
    snd_water.play()
    snd_night = AudioStreamPlayer.new()
    snd_night.stream = _cricket_loop()
    snd_night.volume_db = -80.0
    add_child(snd_night)
    snd_night.play()
    for i in 3:
        steps_grass.append(_burst(0.11, 0.55 + i * 0.05, 0.9, 5.0, 1.1))
        steps_hard.append(_burst(0.07, 0.35 + i * 0.05, 0.8, 7.0, 1.2))
        steps_splash.append(_burst(0.28, 0.6 + i * 0.05, 0.93, 3.5, 1.4))
    chirps = [_chirp(3200, 4600, 0.16, 6), _chirp(2400, 3400, 0.22, 3), _chirp(4200, 2800, 0.12, 9), _chirp(3000, 3800, 0.3, 14)]
    step_player = AudioStreamPlayer.new()
    step_player.volume_db = -9.0
    add_child(step_player)
    # floating pollen and drifting leaves around the player
    pollen = _make_floaters(Color(1.0, 0.97, 0.8, 0.55), 0.035, 140, Vector3(0.15, 0.05, 0.1), 0.0)
    leaves = _make_floaters(Color(0.75, 0.5, 0.15, 1.0), 0.09, 40, Vector3(0.5, -0.45, 0.25), 1.0)


func _make_floaters(col: Color, size: float, amount: int, grav: Vector3, spin: float) -> GPUParticles3D:
    var p := GPUParticles3D.new()
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pm.emission_box_extents = Vector3(18.0, 6.0, 18.0)
    pm.gravity = grav
    pm.direction = Vector3(1, 0, 0.3)
    pm.spread = 180.0
    pm.initial_velocity_min = 0.05
    pm.initial_velocity_max = 0.4
    pm.angular_velocity_min = -90.0 * spin
    pm.angular_velocity_max = 90.0 * spin
    pm.scale_min = 0.7
    pm.scale_max = 1.4
    p.process_material = pm
    var q := QuadMesh.new()
    q.size = Vector2(size, size)
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = col
    if col.a < 1.0:
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    if spin == 0.0:
        m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    q.material = m
    p.draw_pass_1 = q
    p.amount = amount
    p.lifetime = 14.0
    p.preprocess = 14.0
    p.local_coords = false
    p.visibility_aabb = AABB(Vector3(-25, -10, -25), Vector3(50, 20, 50))
    add_child(p)
    return p


func _footstep(speed: float) -> void:
    if step_player == null or player == null:
        return
    var y := player.global_position.y
    var list: Array = steps_grass
    if y < -0.1:
        list = steps_splash
    elif y < 2.0 or y > 15.0:
        list = steps_hard
    var snd: AudioStreamWAV = list[_arng.randi() % list.size()]
    step_player.stream = snd
    step_player.pitch_scale = _arng.randf_range(0.85, 1.15) * (1.0 + clampf(speed - 2.0, 0.0, 3.0) * 0.04)
    step_player.volume_db = -9.0 + clampf(speed - 2.0, 0.0, 3.0) * 1.2
    step_player.play()


func _update_audio(delta: float) -> void:
    if snd_wind == null or player == null:
        return
    var day := clampf(sin((time_of_day - 0.25) * TAU) * 3.0 + 0.5, 0.0, 1.0)
    var t := Time.get_ticks_msec() * 0.001
    var gust := 0.5 + 0.5 * sin(t * 0.21) * sin(t * 0.13 + 1.0)
    var y := player.global_position.y
    var hill := clampf((y - 4.0) / 14.0, 0.0, 1.0)
    snd_wind.volume_db = lerpf(-24.0, -9.0, clampf(gust * 0.6 + hill * 0.6, 0.0, 1.0))
    snd_wind.pitch_scale = 0.9 + gust * 0.2
    # water gets louder near the shore and sea
    var near_water := clampf((3.8 - y) / 3.5, 0.0, 1.0)
    var edge := clampf((Vector2(player.global_position.x, player.global_position.z).length() - R * 0.62) / (R * 0.3), 0.0, 1.0)
    snd_water.volume_db = linear_to_db(maxf(near_water * 0.9 + edge * 0.6, 0.0001)) - 10.0
    snd_night.volume_db = linear_to_db(maxf((1.0 - day) * 0.8, 0.0001)) - 22.0
    # birds sing in the daytime, from somewhere in the trees around you
    bird_timer -= delta
    if bird_timer <= 0.0 and day > 0.4:
        bird_timer = _arng.randf_range(1.5, 6.0)
        var b := AudioStreamPlayer3D.new()
        b.stream = chirps[_arng.randi() % chirps.size()]
        b.pitch_scale = _arng.randf_range(0.85, 1.25)
        b.volume_db = -4.0
        b.unit_size = 6.0
        b.max_distance = 70.0
        var a := _arng.randf() * TAU
        var dist := _arng.randf_range(8.0, 40.0)
        b.position = player.global_position + Vector3(cos(a) * dist, _arng.randf_range(3.0, 9.0), sin(a) * dist)
        add_child(b)
        b.play()
        b.finished.connect(b.queue_free)
        if _arng.randf() < 0.4:
            bird_timer = 0.25 + _arng.randf() * 0.5
    # keep the floating bits around the player
    if pollen != null:
        pollen.global_position = player.global_position + Vector3(0, 3.0, 0)
        pollen.visible = day > 0.3
    if leaves != null:
        leaves.global_position = player.global_position + Vector3(0, 6.0, 0)


# ---------------------------------------------------------------- map
var map_tex: ImageTexture
var map_open := false
var map_marks: Array = []
const MAPRES := 420


func _build_map() -> void:
    var n := MAPRES
    var hs := PackedFloat32Array()
    hs.resize(n * n)
    for j in n:
        for i in n:
            hs[j * n + i] = height_at((i + 0.5) / n * SIZE - SIZE * 0.5, (j + 0.5) / n * SIZE - SIZE * 0.5)
    var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
    for j in n:
        for i in n:
            var h := hs[j * n + i]
            var x := (i + 0.5) / n * SIZE - SIZE * 0.5
            var z := (j + 0.5) / n * SIZE - SIZE * 0.5
            var hl := hs[j * n + maxi(i - 1, 0)]
            var hr := hs[j * n + mini(i + 1, n - 1)]
            var hu := hs[maxi(j - 1, 0) * n + i]
            var hd := hs[mini(j + 1, n - 1) * n + i]
            var slope := Vector2(hr - hl, hd - hu).length() * 0.5
            var shade := clampf(0.82 + (hl - hr) * 0.09 + (hu - hd) * 0.09, 0.45, 1.25)
            var c: Color
            if h < 0.0:
                c = Color(0.05, 0.20, 0.30).lerp(Color(0.22, 0.55, 0.58), clampf((h + 3.5) / 3.5, 0.0, 1.0))
                shade = 1.0
            elif h < 1.5:
                c = Color(0.84, 0.78, 0.57)
            elif slope > 0.62:
                c = Color(0.46, 0.44, 0.41)
            elif h < 1.4 or noise3.get_noise_2d(x * 1.7, z * 1.7) < -0.25:
                c = Color(0.46, 0.60, 0.28)    # open meadow
            elif h > 8.0 or noise2.get_noise_2d(x, z) > 0.1:
                c = Color(0.12, 0.30, 0.16)    # pine forest
            else:
                c = Color(0.20, 0.42, 0.17)    # broadleaf forest
            c = c.lerp(Color(0.9, 0.9, 0.86), clampf((h - 17.0) / 6.0, 0.0, 0.6))
            c = Color(c.r * shade, c.g * shade, c.b * shade)
            if h > 0.0 and absf(fposmod(h + 1.0, 3.0) - 1.5) > 1.42:
                c = c.darkened(0.14)     # contour line every 3 m
            img.set_pixel(i, j, c)
    map_tex = ImageTexture.create_from_image(img)


func world_size() -> float:
    return SIZE


func map_res() -> int:
    return MAPRES


func mini_rect() -> Rect2:
    var s := get_viewport().get_visible_rect().size
    var u := ui_scale()
    var sr := style_rect()
    return Rect2(s.x - 170.0 * u - 12.0, sr.end.y + 8.0, 170.0 * u, 170.0 * u)


func full_map_rect() -> Rect2:
    var s := get_viewport().get_visible_rect().size
    var side := minf(s.x, s.y) * 0.9
    return Rect2((s.x - side) * 0.5, (s.y - side) * 0.5, side, side)


# ---------------------------------------------------------------- online: rooms, other players, voice chat
const SERVER_URL := "wss://verdant-reach.onrender.com/ws"
var ws: WebSocketPeer = null
var net_state := "off"        # off / connecting / online
var net_want := false
var net_room := ""
var net_id := ""
var net_name := "Explorer"
var net_since := 0.0
var net_retry := 0.0
var net_send_t := 0.0
var net_status := ""
var net_tries := 0
var remotes := {}             # id -> {node, label, vplayer, pb, speak}
var online_open := false
var ui_layer: CanvasLayer
var ui_btn: Button
var ui_mic: Button
var ui_panel: PanelContainer
var ui_name: LineEdit
var ui_code: LineEdit
var ui_stat: Label
var ui_leave: Button
var ui_range: Button
var mic_on := true
var voice_nearby := false
var cap: AudioEffectCapture = null
var mic_player: AudioStreamPlayer = null
var voice_ready := false
var voice_note := ""
var vq := PackedFloat32Array()
var rs_sum := 0.0
var rs_cnt := 0
var rs_phase := 0.0
var talk_hang := 0.0
var talking := false


func _online_load() -> void:
    var cf := ConfigFile.new()
    if cf.load("user://online.cfg") == OK:
        net_id = str(cf.get_value("o", "id", ""))
        net_name = str(cf.get_value("o", "name", "Explorer"))
        net_room = str(cf.get_value("o", "room", ""))
    if net_id.length() < 6:
        var chars := "abcdefghjkmnpqrstuvwxyz23456789"
        net_id = ""
        for i in 8:
            net_id += chars[randi() % chars.length()]


func _online_save() -> void:
    var cf := ConfigFile.new()
    cf.set_value("o", "id", net_id)
    cf.set_value("o", "name", net_name)
    cf.set_value("o", "room", net_room)
    cf.save("user://online.cfg")


func _over_ui(p: Vector2) -> bool:
    if ui_btn != null and ui_btn.get_global_rect().has_point(p):
        return true
    if ui_mic != null and ui_mic.visible and ui_mic.get_global_rect().has_point(p):
        return true
    return false


func _ui_font(c: Control, n: int) -> void:
    c.add_theme_font_size_override("font_size", n)


func _build_online_ui() -> void:
    _online_load()
    var u := ui_scale()
    var fs := int(22.0 * u)
    ui_layer = CanvasLayer.new()
    ui_layer.layer = 20
    add_child(ui_layer)
    ui_btn = Button.new()
    ui_btn.text = "ONLINE"
    ui_btn.position = Vector2(14.0, 46.0 * u)
    ui_btn.custom_minimum_size = Vector2(150.0 * u, 44.0 * u)
    _ui_font(ui_btn, fs)
    ui_btn.pressed.connect(_on_online_btn)
    ui_layer.add_child(ui_btn)
    ui_mic = Button.new()
    ui_mic.text = "MIC ON"
    ui_mic.position = Vector2(14.0, 46.0 * u + 50.0 * u)
    ui_mic.custom_minimum_size = Vector2(150.0 * u, 44.0 * u)
    _ui_font(ui_mic, fs)
    ui_mic.visible = false
    ui_mic.pressed.connect(_on_mic_btn)
    ui_layer.add_child(ui_mic)

    ui_panel = PanelContainer.new()
    ui_panel.visible = false
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", int(8.0 * u))
    ui_panel.add_child(vb)
    var t := Label.new()
    t.text = "Play with friends"
    _ui_font(t, int(28.0 * u))
    vb.add_child(t)
    var l1 := Label.new()
    l1.text = "Your name"
    _ui_font(l1, fs)
    vb.add_child(l1)
    ui_name = LineEdit.new()
    ui_name.text = net_name
    ui_name.max_length = 12
    ui_name.custom_minimum_size = Vector2(380.0 * u, 44.0 * u)
    _ui_font(ui_name, fs)
    vb.add_child(ui_name)
    var l2 := Label.new()
    l2.text = "Room code (same code = same world)"
    _ui_font(l2, fs)
    vb.add_child(l2)
    ui_code = LineEdit.new()
    ui_code.text = net_room
    ui_code.max_length = 12
    ui_code.placeholder_text = "e.g. FOXY"
    ui_code.custom_minimum_size = Vector2(380.0 * u, 44.0 * u)
    _ui_font(ui_code, fs)
    vb.add_child(ui_code)
    var hb := HBoxContainer.new()
    hb.add_theme_constant_override("separation", int(8.0 * u))
    vb.add_child(hb)
    var bj := Button.new()
    bj.text = "Join room"
    _ui_font(bj, fs)
    bj.custom_minimum_size = Vector2(180.0 * u, 48.0 * u)
    bj.pressed.connect(_on_join)
    hb.add_child(bj)
    var bn := Button.new()
    bn.text = "New room"
    _ui_font(bn, fs)
    bn.custom_minimum_size = Vector2(180.0 * u, 48.0 * u)
    bn.pressed.connect(_on_newroom)
    hb.add_child(bn)
    ui_range = Button.new()
    ui_range.text = "Voice: everyone hears you"
    _ui_font(ui_range, fs)
    ui_range.pressed.connect(_on_range)
    vb.add_child(ui_range)
    ui_stat = Label.new()
    ui_stat.text = ""
    ui_stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    ui_stat.custom_minimum_size = Vector2(380.0 * u, 0.0)
    _ui_font(ui_stat, int(18.0 * u))
    vb.add_child(ui_stat)
    var hb2 := HBoxContainer.new()
    hb2.add_theme_constant_override("separation", int(8.0 * u))
    vb.add_child(hb2)
    ui_leave = Button.new()
    ui_leave.text = "Leave room"
    _ui_font(ui_leave, fs)
    ui_leave.pressed.connect(_on_leave)
    hb2.add_child(ui_leave)
    var bc := Button.new()
    bc.text = "Close"
    _ui_font(bc, fs)
    bc.custom_minimum_size = Vector2(140.0 * u, 48.0 * u)
    bc.pressed.connect(_on_close_panel)
    hb2.add_child(bc)
    ui_layer.add_child(ui_panel)
    ui_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    ui_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    ui_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
    _ui_refresh()


func _ui_refresh() -> void:
    if ui_btn == null:
        return
    if net_state == "online":
        ui_btn.text = "ROOM %s  (%d)" % [net_room.to_upper(), remotes.size() + 1]
    elif net_state == "connecting":
        ui_btn.text = "CONNECTING..."
    else:
        ui_btn.text = "ONLINE"
    ui_mic.visible = net_state == "online"
    ui_mic.text = "MIC ON" if mic_on else "MIC OFF"
    ui_mic.modulate = Color(0.6, 1.0, 0.6) if (mic_on and talking) else Color(1, 1, 1)
    ui_leave.visible = net_state != "off"
    ui_stat.text = net_status


func _on_online_btn() -> void:
    online_open = true
    ui_panel.visible = true
    stick_id = -1
    stick_vec = Vector2.ZERO
    look_id = -1
    _ui_refresh()


func _on_close_panel() -> void:
    online_open = false
    ui_panel.visible = false


func _on_newroom() -> void:
    var chars := "abcdefghjkmnpqrstuvwxyz"
    var c := ""
    for i in 4:
        c += chars[randi() % chars.length()]
    ui_code.text = c
    _on_join()


func _on_join() -> void:
    net_name = ui_name.text.strip_edges()
    if net_name == "":
        net_name = "Explorer"
    var code := ui_code.text.to_lower()
    var clean := ""
    for ch in code:
        if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
            clean += ch
    if clean == "":
        net_status = "Type a room code first (or tap New room)."
        _ui_refresh()
        return
    net_room = clean
    _online_save()
    net_tries = 0
    _net_connect()
    online_open = false
    ui_panel.visible = false


func _on_leave() -> void:
    _net_close(true)
    net_status = "You left the room."
    _ui_refresh()


func _on_mic_btn() -> void:
    mic_on = not mic_on
    _ui_refresh()


func _on_range() -> void:
    voice_nearby = not voice_nearby
    ui_range.text = "Voice: only nearby players" if voice_nearby else "Voice: everyone hears you"
    for id in remotes.keys():
        _voice_range(remotes[id])


func _net_connect() -> void:
    _net_close(false)
    net_want = true
    net_state = "connecting"
    net_since = Time.get_ticks_msec() * 0.001
    net_status = "Connecting... the free server can take up to a minute to wake up."
    ws = WebSocketPeer.new()
    ws.inbound_buffer_size = 1 << 20
    ws.outbound_buffer_size = 1 << 20
    var url := "%s?room=%s&id=%s" % [SERVER_URL, net_room, net_id]
    if ws.connect_to_url(url) != OK:
        net_state = "off"
        net_status = "Could not start the connection."
    _ui_refresh()


func _net_close(forget: bool) -> void:
    if ws != null:
        ws.close()
    ws = null
    for id in remotes.keys():
        _remote_remove(id)
    if forget:
        net_want = false
    net_state = "off"
    _ui_refresh()


func _net_send_profile() -> void:
    if ws == null or net_state != "online" or player == null:
        return
    var lk := {}
    var pl: Dictionary = player.get("look")
    for g in pl.keys():
        var v = pl[g]
        if v is Color:
            lk[g] = [snappedf(v.r, 0.01), snappedf(v.g, 0.01), snappedf(v.b, 0.01)]
        else:
            lk[g] = false
    var prof := {"n": net_name, "g": int(look.get("g", 0)), "look": lk}
    ws.send_text(JSON.stringify({"t": "p", "p": prof}))


func _net_send_state() -> void:
    var p := player.global_position
    var m: Node3D = player.get("model")
    var yaw := 0.0
    if m != null:
        yaw = m.rotation.y
    var sw := 1 if bool(player.get("swimming")) else 0
    var gr := 1 if player.is_on_floor() else 0
    ws.send_text(JSON.stringify({"t": "s", "s": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(yaw, 0.01), sw, gr, int(player.get("gest"))]}))


func _net_process(delta: float) -> void:
    if ws == null:
        if net_want and net_state == "off":
            net_retry -= delta
            if net_retry <= 0.0 and net_tries < 6:
                net_tries += 1
                _net_connect()
        _ui_refresh_light()
        return
    ws.poll()
    var st := ws.get_ready_state()
    if st == WebSocketPeer.STATE_OPEN:
        if net_state != "online":
            net_state = "online"
            net_tries = 0
            net_status = "Connected! Share the room code %s with your friends." % net_room.to_upper()
            _net_send_profile()
            _voice_start()
            _ui_refresh()
        while ws.get_available_packet_count() > 0:
            var pkt := ws.get_packet()
            if ws.was_string_packet():
                _net_text(pkt.get_string_from_utf8())
            else:
                _net_voice(pkt)
        net_send_t -= delta
        if net_send_t <= 0.0:
            net_send_t = 0.1
            _net_send_state()
        _voice_process(delta)
    elif st == WebSocketPeer.STATE_CLOSED:
        var was_online := net_state == "online"
        for id in remotes.keys():
            _remote_remove(id)
        ws = null
        net_state = "off"
        if net_want:
            net_status = "Connection lost - trying again..." if was_online else "Could not connect - trying again..."
            net_retry = 3.0
        _ui_refresh()
    elif st == WebSocketPeer.STATE_CONNECTING:
        if Time.get_ticks_msec() * 0.001 - net_since > 90.0:
            ws.close()
    _ui_refresh_light()
    _remote_labels()


func _ui_refresh_light() -> void:
    if ui_mic != null and net_state == "online":
        ui_mic.modulate = Color(0.6, 1.0, 0.6) if (mic_on and talking) else Color(1, 1, 1)


func _net_text(txt: String) -> void:
    var m = JSON.parse_string(txt)
    if not (m is Dictionary):
        return
    var t := str(m.get("t", ""))
    if t == "hello":
        time_of_day = float(m.get("tod", time_of_day))
        for pr in m.get("peers", []):
            if pr is Dictionary:
                _remote_add(str(pr.get("id", "")), pr.get("p", null))
                if pr.get("s", null) is Array:
                    _remote_state(str(pr.get("id", "")), pr["s"])
        _ui_refresh()
    elif t == "join" or t == "p":
        _remote_add(str(m.get("id", "")), m.get("p", null))
        _ui_refresh()
    elif t == "s":
        if m.get("s", null) is Array:
            _remote_state(str(m.get("id", "")), m["s"])
    elif t == "leave":
        _remote_remove(str(m.get("id", "")))
        _ui_refresh()
    elif t == "time":
        var v := float(m.get("v", time_of_day))
        if absf(angle_difference(v * TAU, time_of_day * TAU)) > 0.03:
            time_of_day = v
    elif t == "full":
        net_want = false
        net_status = "That room is full (8 players)."
        _ui_refresh()


func _remote_cols(p) -> Dictionary:
    var cols := {}
    if p is Dictionary and p.get("look", null) is Dictionary:
        var lk: Dictionary = p["look"]
        for g in lk.keys():
            var v = lk[g]
            if v is Array and v.size() >= 3:
                cols[g] = Color(float(v[0]), float(v[1]), float(v[2]))
            else:
                cols[g] = false
    return cols


func _remote_add(id: String, p) -> void:
    if id == "" or id == net_id:
        return
    var nm := "Player"
    var gi := 0
    if p is Dictionary:
        nm = str(p.get("n", "Player"))
        gi = clampi(int(p.get("g", 0)), 0, 3)
    var cols := _remote_cols(p)
    if remotes.has(id):
        var r: Dictionary = remotes[id]
        var pl0: Player = r["node"]
        pl0.look = cols
        pl0.char_key = CHAR_KEYS[gi]
        pl0.rebuild()
        (r["label"] as Label3D).text = nm
        return
    var pl := Player.new()
    pl.is_remote = true
    pl.char_key = CHAR_KEYS[gi]
    pl.look = cols
    pl.position = Vector3(0, -50, 0)
    add_child(pl)
    pl.net_pos = Vector3(0, -50, 0)
    var lb := Label3D.new()
    lb.text = nm
    lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    lb.pixel_size = 0.0045
    lb.font_size = 56
    lb.outline_size = 14
    lb.position = Vector3(0, 2.1, 0)
    lb.no_depth_test = true
    lb.fixed_size = false
    pl.add_child(lb)
    var vp := AudioStreamPlayer3D.new()
    var gen := AudioStreamGenerator.new()
    gen.mix_rate = 16000.0
    gen.buffer_length = 0.5
    vp.stream = gen
    vp.volume_db = 6.0
    vp.position = Vector3(0, 1.6, 0)
    pl.add_child(vp)
    vp.play()
    var rec := {"node": pl, "label": lb, "vplayer": vp, "pb": vp.get_stream_playback(), "speak": 0.0, "fresh": true}
    _voice_range(rec)
    remotes[id] = rec


func _voice_range(rec: Dictionary) -> void:
    var vp: AudioStreamPlayer3D = rec["vplayer"]
    if voice_nearby:
        vp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
        vp.unit_size = 9.0
        vp.max_distance = 80.0
    else:
        vp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
        vp.max_distance = 0.0


func _remote_remove(id: String) -> void:
    if not remotes.has(id):
        return
    var r: Dictionary = remotes[id]
    var n: Node = r["node"]
    if is_instance_valid(n):
        n.queue_free()
    remotes.erase(id)


func _remote_state(id: String, s: Array) -> void:
    if not remotes.has(id) or s.size() < 6:
        return
    var r: Dictionary = remotes[id]
    var pl: Player = r["node"]
    pl.net_pos = Vector3(float(s[0]), float(s[1]), float(s[2]))
    pl.net_yaw = float(s[3])
    pl.net_swim = float(s[4]) > 0.5
    pl.net_grounded = float(s[5]) > 0.5
    pl.net_gest = int(float(s[6])) if s.size() > 6 else 0
    if r["fresh"]:
        r["fresh"] = false
        pl.global_position = pl.net_pos


func _remote_labels() -> void:
    var now := Time.get_ticks_msec() * 0.001
    for id in remotes.keys():
        var r: Dictionary = remotes[id]
        var lb: Label3D = r["label"]
        lb.modulate = Color(0.55, 1.0, 0.55) if now < float(r["speak"]) else Color(1, 1, 1)


# ---- voice: microphone -> 16 kHz mu-law -> server -> other players
func _on_perm(perm: String, granted: bool) -> void:
    if perm == "RECORD_AUDIO" and granted:
        _voice_start()


func _voice_start() -> void:
    if voice_ready:
        return
    if OS.get_name() == "Android" and not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
        if not get_tree().on_request_permissions_result.is_connected(_on_perm):
            get_tree().on_request_permissions_result.connect(_on_perm)
        OS.request_permission("RECORD_AUDIO")
        return
    if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
        voice_note = "Voice is off: open Project Settings > Audio > Driver and turn on Enable Input, then restart."
        net_status += "\n" + voice_note
        print(voice_note)
        return
    var idx := AudioServer.get_bus_index("Mic")
    if idx < 0:
        AudioServer.add_bus()
        idx = AudioServer.bus_count - 1
        AudioServer.set_bus_name(idx, "Mic")
        AudioServer.set_bus_volume_db(idx, -60.0)
        cap = AudioEffectCapture.new()
        cap.buffer_length = 0.5
        AudioServer.add_bus_effect(idx, cap)
    else:
        cap = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
    mic_player = AudioStreamPlayer.new()
    mic_player.stream = AudioStreamMicrophone.new()
    mic_player.bus = "Mic"
    add_child(mic_player)
    mic_player.play()
    voice_ready = cap != null
    print("Voice: microphone started")


func _mulaw_enc(x: float) -> int:
    var s := clampf(x, -1.0, 1.0)
    var sign_bit := 128 if s < 0.0 else 0
    var mag := log(1.0 + 255.0 * absf(s)) / log(256.0)
    return sign_bit | int(round(mag * 127.0))


func _mulaw_dec(b: int) -> float:
    var mag := float(b & 127) / 127.0
    var v := (pow(256.0, mag) - 1.0) / 255.0
    return -v if (b & 128) != 0 else v


func _voice_process(_delta: float) -> void:
    if not voice_ready or cap == null:
        return
    var n := cap.get_frames_available()
    if n <= 0:
        return
    var buf := cap.get_buffer(n)
    var step := AudioServer.get_mix_rate() / 16000.0
    for i in buf.size():
        rs_sum += (buf[i].x + buf[i].y) * 0.5
        rs_cnt += 1
        rs_phase += 1.0
        if rs_phase >= step:
            rs_phase -= step
            vq.append(rs_sum / float(rs_cnt))
            rs_sum = 0.0
            rs_cnt = 0
    while vq.size() >= 320:
        var chunk := vq.slice(0, 320)
        vq = vq.slice(320)
        var e := 0.0
        for v in chunk:
            e += v * v
        var rms := sqrt(e / 320.0)
        if rms > 0.012:
            talk_hang = 0.35
        else:
            talk_hang = maxf(0.0, talk_hang - 0.02)
        talking = talk_hang > 0.0 and mic_on
        if talking:
            var out := PackedByteArray()
            out.resize(320)
            for k in 320:
                out[k] = _mulaw_enc(chunk[k] * 2.0)
            ws.send(out)
    if vq.size() > 8000:
        vq.clear()


func _net_voice(pkt: PackedByteArray) -> void:
    if pkt.size() < 3:
        return
    var il := int(pkt[0])
    if pkt.size() < 1 + il + 2:
        return
    var id := pkt.slice(1, 1 + il).get_string_from_ascii()
    if not remotes.has(id):
        return
    var r: Dictionary = remotes[id]
    var pbv = r["pb"]
    if pbv == null:
        return
    var count := pkt.size() - 1 - il
    if int(pbv.get_frames_available()) < count:
        return
    var fr := PackedVector2Array()
    fr.resize(count)
    for k in count:
        var v := _mulaw_dec(int(pkt[1 + il + k]))
        fr[k] = Vector2(v, v)
    pbv.push_buffer(fr)
    r["speak"] = Time.get_ticks_msec() * 0.001 + 0.4


# ---------------------------------------------------------------- customisation menu
func _make_palettes() -> void:
    var cloth := [Color(0.70, 0.15, 0.15), Color(0.85, 0.50, 0.15), Color(0.85, 0.75, 0.20), Color(0.20, 0.50, 0.25),
        Color(0.15, 0.50, 0.50), Color(0.20, 0.35, 0.75), Color(0.50, 0.25, 0.65), Color(0.90, 0.90, 0.88),
        Color(0.35, 0.35, 0.37), Color(0.08, 0.08, 0.09), Color(0.40, 0.27, 0.15), Color(0.76, 0.62, 0.40)]
    pal["skin"] = [Color(0.96, 0.80, 0.68), Color(0.88, 0.68, 0.52), Color(0.75, 0.55, 0.41), Color(0.60, 0.42, 0.30),
        Color(0.45, 0.30, 0.21), Color(0.30, 0.20, 0.14)]
    pal["hair"] = [Color(0.05, 0.05, 0.06), Color(0.18, 0.10, 0.07), Color(0.35, 0.20, 0.10), Color(0.85, 0.72, 0.40),
        Color(0.62, 0.25, 0.10), Color(0.60, 0.60, 0.62), Color(0.92, 0.92, 0.92), Color(0.20, 0.30, 0.70), Color(0.90, 0.40, 0.60)]
    pal["tint"] = cloth
    pal["top"] = cloth
    pal["pants"] = cloth
    pal["scarf"] = cloth
    pal["pack"] = cloth
    pal["boots"] = [Color(0.06, 0.06, 0.07), Color(0.19, 0.12, 0.08), Color(0.55, 0.40, 0.25), Color(0.45, 0.45, 0.47),
        Color(0.90, 0.90, 0.88), Color(0.70, 0.15, 0.15)]
    pal["eyes"] = [Color(0.30, 0.18, 0.10), Color(0.20, 0.40, 0.80), Color(0.20, 0.55, 0.30), Color(0.50, 0.52, 0.55),
        Color(0.55, 0.35, 0.65)]


func _load_look() -> void:
    look = {"g": 0}   # 0 Boy, 1 Girl, 2 Explorer M, 3 Explorer F
    var cf := ConfigFile.new()
    if cf.load("user://look.cfg") == OK:
        for k in cf.get_section_keys("look"):
            look[k] = int(cf.get_value("look", k, -1))


func _save_look() -> void:
    var cf := ConfigFile.new()
    for k in look.keys():
        cf.set_value("look", k, int(look[k]))
    cf.save("user://look.cfg")


func apply_look() -> void:
    var cols := {}
    for g in pal.keys():
        var i := int(look.get(g, -1))
        if i == -2:
            cols[g] = false
        elif i >= 0 and i < pal[g].size():
            cols[g] = pal[g][i]
    player.set("look", cols)
    player.set("char_key", CHAR_KEYS[clampi(int(look.get("g", 0)), 0, 3)])
    player.call("rebuild")
    _save_look()
    _net_send_profile()


func ui_scale() -> float:
    var s := get_viewport().get_visible_rect().size
    return clampf(minf(s.x / 900.0, s.y / 640.0), 0.6, 1.6)


func style_rect() -> Rect2:
    var s := get_viewport().get_visible_rect().size
    var u := ui_scale()
    return Rect2(s.x - 150.0 * u - 12.0, 10.0, 150.0 * u, 46.0 * u)


# items: {rect, group, idx, color, text}
func menu_items() -> Array:
    var out: Array = []
    var s := get_viewport().get_visible_rect().size
    var u := ui_scale()
    var pw := minf(s.x - 24.0, 880.0 * u)
    var x0 := (s.x - pw) * 0.5
    var y := 20.0 * u + 60.0 * u
    out.append({"rect": Rect2(x0 + pw - 130.0 * u, 20.0 * u + 8.0 * u, 120.0 * u, 44.0 * u), "group": "done", "idx": 0, "text": "DONE"})
    for ci in 4:
        out.append({"rect": Rect2(x0 + (150.0 + ci * 160.0) * u, y, 150.0 * u, 44.0 * u), "group": "g", "idx": ci, "text": CHAR_NAMES[ci]})
    y += 56.0 * u
    for row in LOOK_ROWS:
        var g: String = row[0]
        var x := x0 + 150.0 * u
        var sw := 40.0 * u
        out.append({"rect": Rect2(x, y, sw, sw), "group": g, "idx": -1, "text": "A"})
        x += sw + 8.0 * u
        if g == "scarf" or g == "pack":
            out.append({"rect": Rect2(x, y, sw, sw), "group": g, "idx": -2, "text": "X"})
            x += sw + 8.0 * u
        for i in pal[g].size():
            out.append({"rect": Rect2(x, y, sw, sw), "group": g, "idx": i, "color": pal[g][i], "text": ""})
            x += sw + 8.0 * u
        y += 52.0 * u
    return out


func _menu_tap(p: Vector2) -> void:
    for it in menu_items():
        if (it["rect"] as Rect2).has_point(p):
            if it["group"] == "done":
                menu_open = false
            else:
                look[it["group"]] = it["idx"]
                apply_look()
            return


# ---------------------------------------------------------------- inner classes
class Player extends CharacterBody3D:
    # Third-person explorer with a hand-animated humanoid (no model files needed).

    var move_input := Vector2.ZERO   # x = right, y = back (negative = forward)
    var want_run := false
    var is_remote := false
    var net_pos := Vector3.ZERO
    var net_yaw := 0.0
    var net_swim := false
    var net_grounded := true
    var step_cb := Callable()
    var last_step := 0
    var cam_yaw := 0.0
    var cam_pitch := -0.28
    var cam_dist := 4.2

    const WALK_SPEED := 2.0
    const RUN_SPEED := 5.2
    const ACCEL := 14.0
    const DECEL := 18.0
    const JUMP_V := 5.0
    const GRAV := 14.0
    const PELVIS_Y := 0.93
    # Change to res://chars/Verdant_Reach_Female_Explorer.glb for the female character
    const MODEL_PATH := "res://chars/Verdant_Reach_Male_Explorer.glb"
    const MODEL_SCALE := 0.92
    var base_y := 0.93
    var model_path := MODEL_PATH
    var char_key := "boy"           # boy, girl (rigged) or male, female (parts model)
    var rig_skel: Skeleton3D = null
    var rig_bone := {}
    var rig_hang := 64.0
    const RIGS := {
        "boy": {"path": "res://chars/char_boy.glb", "tex": "res://chars/Boy_02", "hang": 64.0},
        "girl": {"path": "res://chars/char_girl.glb", "tex": "res://chars/FantasyGirl_01", "hang": 84.0}}
    var look := {}      # group -> Color (custom) or false (hidden); missing = model default
    var _mats := {}

    var model: Node3D
    var pelvis: Node3D
    var spine: Node3D
    var neck: Node3D
    var thigh: Array = [null, null]
    var knee: Array = [null, null]
    var foot: Array = [null, null]
    var uarm: Array = [null, null]
    var farm: Array = [null, null]
    var cam_pivot: Node3D
    var spring: SpringArm3D
    var cam: Camera3D

    var phase := 0.0
    var amp := 0.0
    var t := 0.0
    var lean_fwd := 0.0
    var lean_side := 0.0
    var squat := 0.0
    var swimming := false
    var swim := 0.0
    var swim_ph := 0.0
    var last_sw := 0
    var air := 0.0
    var prev_vel := Vector3.ZERO
    var prev_vy := 0.0
    var was_on_floor := true
    var turn_rate := 0.0
    var gest := 0            # current gesture id (0 = none)
    var gest_t := 0.0
    var gest_dur := 0.0
    var gb := 0.0            # gesture blend 0..1
    var net_gest := 0
    const GEST := [
        ["", 0.0], ["Wave", 3.4], ["Dance", 8.0], ["Clap", 3.2], ["Cheer", 3.2], ["Sit", 0.0], ["Bow", 2.2],
        ["Swing", 1.0], ["Throw", 0.9], ["Eat", 2.4], ["Give", 1.3], ["Point", 2.5], ["Salute", 2.0], ["Shrug", 2.0],
        ["Flex", 3.0], ["Pet", 2.5], ["Drink", 2.2], ["Cast", 1.6], ["Cook", 2.6], ["Stretch", 3.0], ["Laugh", 2.8],
        ["Thumbs up", 2.4], ["Sleep", 0.0], ["Think", 4.0], ["Spin", 1.4], ["Fist pump", 2.0]]


    func play_gesture(id: int) -> void:
        if id <= 0 or id >= GEST.size():
            gest = 0
            return
        if swimming:
            return
        gest = id
        gest_t = 0.0
        gest_dur = float(GEST[id][1])


    func _ready() -> void:
        floor_max_angle = deg_to_rad(55.0)
        floor_snap_length = 0.5
        floor_stop_on_slope = true
        floor_constant_speed = true

        if not is_remote:
            var col := CollisionShape3D.new()
            var cap := CapsuleShape3D.new()
            cap.radius = 0.3
            cap.height = 1.8
            col.shape = cap
            col.position = Vector3(0, 0.9, 0)
            add_child(col)

        _build_body()
        if not is_remote:
            _build_camera()


    func _mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = c
        m.roughness = rough
        return m


    func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
        var n := Node3D.new()
        n.position = pos
        parent.add_child(n)
        return n


    func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.position = pos
        mi.material_override = mat
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        parent.add_child(mi)
        return mi


    func _capsule(r: float, h: float) -> CapsuleMesh:
        var c := CapsuleMesh.new()
        c.radius = r
        c.height = h
        c.radial_segments = 12
        c.rings = 4
        return c


    # ---- real character model (GLB, split into named body parts) ----
    func _rx(v: Vector3) -> Vector3:
        return Vector3(v.x, v.z, -v.y)   # model is Z-up, faces +Y -> Godot Y-up, faces -Z


    func _ab(src: Node, nm: String) -> AABB:
        var n := src.find_child(nm, true, false) as MeshInstance3D
        if n == null or n.mesh == null:
            return AABB()
        return n.mesh.get_aabb()


    func _group(nm: String) -> String:
        var b := nm.trim_prefix("L_").trim_prefix("R_")
        if b in ["neck", "head", "ear", "ear_1", "nose", "forearm", "hand"]:
            return "skin"
        if b in ["hair_cap", "hair_fringe", "side_lock", "side_lock_1", "long_hair_back", "long_hair_lock", "long_hair_lock_1"]:
            return "hair"
        if b in ["torso", "upper_chest", "shoulder", "upper_arm", "elbow"]:
            return "top"
        if b in ["hips", "thigh", "knee", "lower_leg"]:
            return "pants"
        if b == "boot":
            return "boots"
        if b in ["iris", "iris_1"]:
            return "eyes"
        if b == "neck_scarf":
            return "scarf"
        if b in ["backpack", "pack_top", "backpack_strap", "backpack_strap_1", "side_pouch"]:
            return "pack"
        return ""


    func _mat_for(group: String) -> Material:
        if _mats.has(group):
            return _mats[group]
        var m := StandardMaterial3D.new()
        m.roughness = 0.8
        if look.has(group) and look[group] is Color:
            m.albedo_color = look[group]
            if group == "skin":
                m.roughness = 0.62
        else:
            m.vertex_color_use_as_albedo = true
            m.vertex_color_is_srgb = true
        _mats[group] = m
        return m


    func rebuild() -> void:
        var yaw := 0.0
        if model != null:
            yaw = model.rotation.y
            model.free()
        rig_skel = null
        _build_body()
        model.rotation.y = yaw


    func _attach(src: Node, nm: String, piv: Node3D, j: Vector3) -> void:
        var n := src.find_child(nm, true, false) as MeshInstance3D
        if n == null or n.mesh == null:
            return
        var grp := _group(nm)
        if look.has(grp) and look[grp] is bool:
            return
        var mi := MeshInstance3D.new()
        mi.mesh = n.mesh
        mi.material_override = _mat_for(grp)
        mi.position = -_rx(j)
        mi.rotation.x = -PI / 2.0
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        piv.add_child(mi)


    func _scene_from_file(path: String) -> Node:
        if ResourceLoader.exists(path):
            var ps := load(path) as PackedScene
            if ps != null:
                return ps.instantiate()
        if FileAccess.file_exists(path):
            var doc := GLTFDocument.new()
            var st := GLTFState.new()
            if doc.append_from_file(path, st) == OK:
                return doc.generate_scene(st)
        return null


    func _build_model_body() -> bool:
        var src := _scene_from_file(model_path)
        if src == null:
            return false
        if src == null or src.find_child("hips", true, false) == null:
            return false

        _mats = {}
        var hips := _ab(src, "hips")
        var cy := hips.get_center().y
        var hip_z := _ab(src, "L_thigh").end.z
        var j_p := Vector3(0, cy, hip_z)
        var j_sp := Vector3(0, cy, hip_z + 0.04)
        var nk := _ab(src, "neck")
        var j_nk := Vector3(0, nk.get_center().y, nk.position.z)

        model = Node3D.new()
        model.scale = Vector3.ONE * MODEL_SCALE
        add_child(model)
        base_y = hip_z
        pelvis = _pivot(model, Vector3(0, hip_z, 0))
        for nm in ["hips", "belt", "belt_buckle", "side_pouch"]:
            _attach(src, nm, pelvis, j_p)

        spine = _pivot(pelvis, _rx(j_sp - j_p))
        for nm in ["torso", "upper_chest", "backpack", "pack_top", "backpack_strap", "backpack_strap_1", "neck_scarf"]:
            _attach(src, nm, spine, j_sp)

        neck = _pivot(spine, _rx(j_nk - j_sp))
        for nm in ["neck", "head", "ear", "ear_1", "hair_cap", "hair_fringe", "side_lock", "side_lock_1",
                "long_hair_back", "long_hair_lock", "long_hair_lock_1", "eye_white", "eye_white_1",
                "iris", "iris_1", "nose"]:
            _attach(src, nm, neck, j_nk)

        for i in 2:
            var sd := "L" if i == 0 else "R"
            var ta := _ab(src, sd + "_thigh")
            var j_h := Vector3(ta.get_center().x, ta.get_center().y, ta.end.z)
            var th := _pivot(pelvis, _rx(j_h - j_p))
            _attach(src, sd + "_thigh", th, j_h)
            var j_k := _ab(src, sd + "_knee").get_center()
            var kn := _pivot(th, _rx(j_k - j_h))
            _attach(src, sd + "_knee", kn, j_k)
            _attach(src, sd + "_lower_leg", kn, j_k)
            var la := _ab(src, sd + "_lower_leg")
            var j_a := Vector3(la.get_center().x, la.get_center().y, la.position.z)
            var ft := _pivot(kn, _rx(j_a - j_k))
            _attach(src, sd + "_boot", ft, j_a)
            thigh[i] = th
            knee[i] = kn
            foot[i] = ft

            var ua := _ab(src, sd + "_upper_arm")
            var j_s := Vector3(ua.get_center().x, ua.get_center().y, ua.end.z - 0.05)
            var sh := _pivot(spine, _rx(j_s - j_sp))
            _attach(src, sd + "_shoulder", sh, j_s)
            _attach(src, sd + "_upper_arm", sh, j_s)
            var j_e := _ab(src, sd + "_elbow").get_center()
            var el := _pivot(sh, _rx(j_e - j_s))
            for nm in ["_elbow", "_forearm", "_hand"]:
                _attach(src, sd + nm, el, j_e)
            uarm[i] = sh
            farm[i] = el

        src.free()
        return true


    # ---- rigged characters (skeleton built for the Blender meshes) ----
    func _tex_if(path: String) -> Texture2D:
        if ResourceLoader.exists(path):
            return load(path) as Texture2D
        if FileAccess.file_exists(path):
            var img := Image.load_from_file(path)
            if img != null and not img.is_empty():
                img.generate_mipmaps()
                return ImageTexture.create_from_image(img)
        return null


    func _q(rx: float, ry: float, rz: float) -> Quaternion:
        return Basis.from_euler(Vector3(rx, ry, rz)).get_rotation_quaternion()


    # one body part (skin / hair / top / pants / boots): real texture, tinted with the colour picked in STYLE
    func _part_mat(nm: String, fallback: StandardMaterial3D) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.roughness = 0.75 if nm != "skin" else 0.6
        var a := _tex_if("res://chars/pbr/%s_albedo.jpg" % nm)
        print("RIG part ", nm, " texture: ", a != null)
        if a != null:
            m.albedo_texture = a
            m.uv1_triplanar = true
            m.uv1_scale = Vector3(2.2, 2.2, 2.2)
            var n := _tex_if("res://chars/pbr/%s_normal.jpg" % nm)
            if n != null:
                m.normal_enabled = true
                m.normal_texture = n
                m.normal_scale = 0.7
        var c := Color(1, 1, 1)
        if look.has(nm) and look[nm] is Color and a == null:
            c = look[nm]
        elif look.has(nm) and look[nm] is Color:
            c = look[nm]
            c = c.lerp(Color(1, 1, 1), 0.35)
        elif a == null:
            var flat := {"skin": Color(0.86, 0.64, 0.52), "hair": Color(0.10, 0.08, 0.07), "top": Color(0.16, 0.34, 0.20),
                "pants": Color(0.17, 0.17, 0.19), "boots": Color(0.25, 0.15, 0.08)}
            c = flat.get(nm, fallback.albedo_color)
        m.albedo_color = c
        if a != null:
            # lift the dark cloth/hair a little so the character is not a black silhouette in forest shade
            m.emission_enabled = true
            m.emission_texture = a
            m.emission_energy_multiplier = 0.12 if nm == "skin" else 0.45
            m.emission = c
        m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        return m


    func _build_rigged_body(key: String) -> bool:
        var info: Dictionary = RIGS[key]
        var inst := _scene_from_file(str(info["path"]))
        if inst == null:
            return false
        var sks := inst.find_children("*", "Skeleton3D", true, false)
        if sks.is_empty():
            inst.free()
            return false
        rig_skel = sks[0] as Skeleton3D
        rig_hang = float(info["hang"])
        rig_bone = {}
        for i in rig_skel.get_bone_count():
            rig_bone[rig_skel.get_bone_name(i)] = i
        if not rig_bone.has("hips"):
            inst.free()
            return false

        var mat := StandardMaterial3D.new()
        mat.roughness = 0.8
        var base := _tex_if(str(info["tex"]) + "_basecolor.jpg")
        if base != null:
            mat.albedo_texture = base
        else:
            mat.albedo_color = Color(0.78, 0.74, 0.70)
        var nrm := _tex_if(str(info["tex"]) + "_normal.jpg")
        if nrm != null:
            mat.normal_enabled = true
            mat.normal_texture = nrm
        var rgh := _tex_if(str(info["tex"]) + "_roughness.jpg")
        if rgh != null:
            mat.roughness_texture = rgh
            mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
            mat.roughness = 1.0
        if look.has("tint") and look["tint"] is Color:
            mat.albedo_color = look["tint"]
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        var parts := {}
        for nm in ["skin", "hair", "top", "pants", "boots"]:
            parts[nm] = _part_mat(nm, mat)
        for mi in inst.find_children("*", "MeshInstance3D", true, false):
            var mm := mi as MeshInstance3D
            var any_part := false
            if mm.mesh != null:
                var cnt := mm.mesh.get_surface_count()
                var order: Array = ["skin", "hair", "top", "pants", "boots"]
                if cnt == 4:
                    order = ["skin", "hair", "top", "boots"]
                var names: Array = []
                for si in cnt:
                    var sm := mm.mesh.surface_get_material(si)
                    names.append(sm.resource_name if sm != null else "")
                print("RIG surfaces: ", cnt, " names: ", names)
                for si in cnt:
                    var nm: String = names[si]
                    if not parts.has(nm) and cnt >= 4 and si < order.size():
                        nm = order[si]
                    if parts.has(nm):
                        mm.set_surface_override_material(si, parts[nm])
                        any_part = true
            if not any_part:
                mm.material_override = mat
            mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            mm.extra_cull_margin = 2.0

        model = Node3D.new()
        add_child(model)
        model.add_child(inst)
        # proxy nodes (not in the tree): the old animation code writes to these, _apply_rig copies to bones
        base_y = rig_skel.get_bone_rest(int(rig_bone["hips"])).origin.y
        pelvis = Node3D.new()
        pelvis.position = Vector3(0, base_y, 0)
        spine = Node3D.new()
        neck = Node3D.new()
        for i in 2:
            thigh[i] = Node3D.new()
            knee[i] = Node3D.new()
            foot[i] = Node3D.new()
            uarm[i] = Node3D.new()
            farm[i] = Node3D.new()
        return true


    func _apply_rig() -> void:
        if rig_skel == null:
            return
        var sk := rig_skel
        var hi: int = rig_bone["hips"]
        var rest := sk.get_bone_rest(hi)
        sk.set_bone_pose_position(hi, rest.origin + Vector3(0, pelvis.position.y - base_y, 0))
        var q_h := _q(pelvis.rotation.x, pelvis.rotation.y, pelvis.rotation.z)
        sk.set_bone_pose_rotation(hi, q_h)
        var q_sp := _q(spine.rotation.x, spine.rotation.y, spine.rotation.z)
        sk.set_bone_pose_rotation(int(rig_bone["spine"]), q_sp)
        sk.set_bone_pose_rotation(int(rig_bone["neck"]), _q(neck.rotation.x, neck.rotation.y, neck.rotation.z))
        for i in 2:
            var sd := "L" if i == 0 else "R"
            sk.set_bone_pose_rotation(int(rig_bone["thigh_" + sd]), _q(thigh[i].rotation.x, 0.0, 0.0))
            sk.set_bone_pose_rotation(int(rig_bone["shin_" + sd]), _q(knee[i].rotation.x, 0.0, 0.0))
            sk.set_bone_pose_rotation(int(rig_bone["foot_" + sd]), _q(foot[i].rotation.x, 0.0, 0.0))
            var hang := deg_to_rad(rig_hang) * (1.0 if i == 0 else -1.0)
            var q_ua := _q(uarm[i].rotation.x, 0.0, uarm[i].rotation.z + hang)
            sk.set_bone_pose_rotation(int(rig_bone["upperarm_" + sd]), q_ua)
            var qx := Quaternion(Vector3.RIGHT, farm[i].rotation.x)
            sk.set_bone_pose_rotation(int(rig_bone["forearm_" + sd]), q_ua.inverse() * qx * q_ua)


    func _build_body() -> void:
        if RIGS.has(char_key) and _build_rigged_body(char_key):
            return
        if char_key == "male":
            model_path = "res://chars/Verdant_Reach_Male_Explorer.glb"
        elif char_key == "female":
            model_path = "res://chars/Verdant_Reach_Female_Explorer.glb"
        if _build_model_body():
            return
        print("Character model not found in res://chars/ - using simple body")
        var skin := _mat(Color(0.86, 0.68, 0.55), 0.7)
        var shirt := _mat(Color(0.30, 0.38, 0.22))
        var pants := _mat(Color(0.30, 0.25, 0.20))
        var boots := _mat(Color(0.16, 0.11, 0.08), 0.6)
        var hair := _mat(Color(0.18, 0.10, 0.07), 0.6)
        var pack := _mat(Color(0.45, 0.30, 0.16))
        var dark := _mat(Color(0.05, 0.05, 0.06), 0.3)

        model = Node3D.new()
        add_child(model)
        pelvis = _pivot(model, Vector3(0, PELVIS_Y, 0))
        _part(pelvis, _capsule(0.16, 0.3), Vector3(0, 0.02, 0), pants)

        for i in 2:
            var s := -1.0 if i == 0 else 1.0
            var th := _pivot(pelvis, Vector3(s * 0.1, 0.0, 0.0))
            _part(th, _capsule(0.085, 0.46), Vector3(0, -0.23, 0), pants)
            var kn := _pivot(th, Vector3(0, -0.45, 0))
            _part(kn, _capsule(0.07, 0.44), Vector3(0, -0.22, 0), pants)
            var ft := _pivot(kn, Vector3(0, -0.44, 0))
            var box := BoxMesh.new()
            box.size = Vector3(0.11, 0.08, 0.27)
            _part(ft, box, Vector3(0, -0.03, -0.06), boots)
            thigh[i] = th
            knee[i] = kn
            foot[i] = ft

        spine = _pivot(pelvis, Vector3(0, 0.05, 0))
        var torso := _part(spine, _capsule(0.17, 0.62), Vector3(0, 0.3, 0), shirt)
        torso.scale = Vector3(1.0, 1.0, 0.72)
        var bp := BoxMesh.new()
        bp.size = Vector3(0.28, 0.36, 0.14)
        _part(spine, bp, Vector3(0, 0.34, 0.15), pack)

        neck = _pivot(spine, Vector3(0, 0.62, 0))
        var sph := SphereMesh.new()
        sph.radius = 0.115
        sph.height = 0.23
        _part(neck, sph, Vector3(0, 0.12, 0), skin)
        var hs := SphereMesh.new()
        hs.radius = 0.122
        hs.height = 0.2
        var hm := _part(neck, hs, Vector3(0, 0.17, 0.015), hair)
        hm.scale = Vector3(1.0, 0.9, 1.05)
        var es := SphereMesh.new()
        es.radius = 0.015
        es.height = 0.03
        _part(neck, es, Vector3(-0.045, 0.125, -0.105), dark)
        _part(neck, es, Vector3(0.045, 0.125, -0.105), dark)

        for i in 2:
            var s := -1.0 if i == 0 else 1.0
            var sh := _pivot(spine, Vector3(s * 0.23, 0.52, 0))
            _part(sh, _capsule(0.05, 0.32), Vector3(0, -0.15, 0), shirt)
            var el := _pivot(sh, Vector3(0, -0.3, 0))
            _part(el, _capsule(0.045, 0.28), Vector3(0, -0.13, 0), skin)
            var hd := SphereMesh.new()
            hd.radius = 0.05
            hd.height = 0.1
            _part(el, hd, Vector3(0, -0.29, 0), skin)
            uarm[i] = sh
            farm[i] = el


    func _build_camera() -> void:
        cam_pivot = Node3D.new()
        cam_pivot.position = Vector3(0, 1.5, 0)
        add_child(cam_pivot)
        spring = SpringArm3D.new()
        spring.spring_length = cam_dist
        var ss := SphereShape3D.new()
        ss.radius = 0.25
        spring.shape = ss
        spring.add_excluded_object(get_rid())
        cam_pivot.add_child(spring)
        cam = Camera3D.new()
        cam.fov = 70.0
        cam.near = 0.1
        cam.far = 900.0
        spring.add_child(cam)
        cam.current = true


    func jump() -> void:
        if is_on_floor() and not swimming:
            velocity.y = JUMP_V


    func _remote_step(delta: float) -> void:
        var old := global_position
        global_position = global_position.lerp(net_pos, 1.0 - exp(-10.0 * delta))
        var hv := global_position - old
        hv.y = 0.0
        hv = hv / maxf(delta, 0.0001)
        swimming = net_swim
        swim = lerpf(swim, 1.0 if swimming else 0.0, 1.0 - exp(-5.0 * delta))
        if net_gest != gest and not (net_gest > 0 and gest_dur > 0.0 and gest == net_gest):
            if net_gest > 0:
                play_gesture(net_gest)
            else:
                gest = 0
        if model != null:
            model.rotation.y = lerp_angle(model.rotation.y, net_yaw, 1.0 - exp(-10.0 * delta))
            turn_rate = 0.0
            _animate(delta, hv)
            _apply_rig()
        prev_vel = hv


    func _physics_process(delta: float) -> void:
        if is_remote:
            _remote_step(delta)
            return
        var inp := move_input
        if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
            inp.y -= 1.0
        if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
            inp.y += 1.0
        if Input.is_key_pressed(KEY_A):
            inp.x -= 1.0
        if Input.is_key_pressed(KEY_D):
            inp.x += 1.0
        if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q):
            cam_yaw += 1.8 * delta
        if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_E):
            cam_yaw -= 1.8 * delta
        if Input.is_key_pressed(KEY_SPACE):
            jump()
        inp = inp.limit_length(1.0)
        var running := want_run or Input.is_key_pressed(KEY_SHIFT)
        var max_speed := RUN_SPEED if running else WALK_SPEED
        var gh := 0.0
        var par := get_parent()
        if par != null and par.has_method("height_at"):
            gh = float(par.call("height_at", global_position.x, global_position.z))
        swimming = gh < -1.1
        swim = lerpf(swim, 1.0 if swimming else 0.0, 1.0 - exp(-5.0 * delta))
        if swimming:
            max_speed = 2.8 if running else 1.7
        elif global_position.y < -0.1:
            max_speed *= 0.6

        var yaw_basis := Basis(Vector3.UP, cam_yaw)
        var dir := yaw_basis * Vector3(inp.x, 0.0, inp.y)
        var target := dir * max_speed * (1.0 if running else inp.length())
        var hv := Vector3(velocity.x, 0.0, velocity.z)
        var rate := ACCEL if target.length() > hv.length() else DECEL
        hv = hv.move_toward(target, rate * delta)
        velocity.x = hv.x
        velocity.z = hv.z

        if swimming:
            # float on the water: spring toward the surface with a little wave bob
            var surf := -0.4 + sin(Time.get_ticks_msec() * 0.002) * 0.04
            velocity.y = clampf((surf - global_position.y) * 5.0, -3.0, 3.0)
        elif is_on_floor():
            velocity.y = maxf(velocity.y, -1.0)
        else:
            velocity.y -= GRAV * delta

        prev_vel = Vector3(hv.x, 0.0, hv.z)
        if gest > 0 and (inp.length() > 0.25 or not is_on_floor() or swimming):
            gest = 0
        elif gest > 0 and gest_dur > 0.0 and gest_t > gest_dur:
            gest = 0
        if gest > 0:
            velocity.x = 0.0
            velocity.z = 0.0
        move_and_slide()

        if is_on_floor() and not was_on_floor and prev_vy < -3.0:
            squat = clampf(-prev_vy * 0.06, 0.1, 0.45)
        was_on_floor = is_on_floor()
        prev_vy = velocity.y

        # face the way we are going
        if dir.length() > 0.1 and hv.length() > 0.3:
            var want := atan2(-dir.x, -dir.z)
            var before := model.rotation.y
            model.rotation.y = lerp_angle(model.rotation.y, want, 1.0 - exp(-10.0 * delta))
            turn_rate = angle_difference(before, model.rotation.y) / maxf(delta, 0.0001)
        else:
            turn_rate = lerpf(turn_rate, 0.0, 1.0 - exp(-8.0 * delta))

        cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
        _animate(delta, hv)
        _apply_rig()


    func _animate(delta: float, hv: Vector3) -> void:
        t += delta
        var speed := hv.length()
        var k := 1.0 - exp(-12.0 * delta)
        amp = lerpf(amp, clampf(speed / 1.2, 0.0, 1.0), k)
        var on_floor := is_on_floor() or (is_remote and net_grounded)
        air = lerpf(air, 0.0 if (on_floor or swimming) else 1.0, 1.0 - exp(-14.0 * delta))
        squat = move_toward(squat, 0.0, delta * 1.4)

        var run_t := clampf((speed - 2.0) / 3.2, 0.0, 1.0)
        phase += delta * speed * lerpf(4.4, 3.1, run_t)
        var sd := int(floor(phase / PI))
        if sd != last_step:
            last_step = sd
            if on_floor and speed > 0.8 and step_cb.is_valid():
                step_cb.call(speed)
        var swing := clampf(0.25 + 0.14 * speed, 0.0, 1.0)

        # acceleration -> body lean
        var acc := (hv - prev_vel) / maxf(delta, 0.0001)
        var fwd := Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y)) * -1.0
        var acc_f := acc.dot(fwd)
        var lean_target := 0.04 + 0.22 * clampf(speed / RUN_SPEED, 0.0, 1.0) + clampf(acc_f * 0.012, -0.12, 0.12)
        lean_fwd = lerpf(lean_fwd, lean_target, 1.0 - exp(-8.0 * delta))
        lean_side = lerpf(lean_side, clampf(-turn_rate * 0.05, -0.25, 0.25) * clampf(speed / 3.0, 0.0, 1.0), 1.0 - exp(-8.0 * delta))

        var sp0 := 0.0
        for i in 2:
            var p := phase + (PI if i == 1 else 0.0)
            var s := sin(p)
            var c := cos(p)
            var th := s * swing * amp
            var flex := maxf(0.0, c) * swing * 1.3 * amp + 0.04
            var arm_s := -s * swing * 0.9 * amp
            var side := -1.0 if i == 0 else 1.0
            if i == 0:
                sp0 = s
            # airborne tuck
            var a_th := 0.55 if i == 0 else -0.25
            var a_fl := 0.95 if i == 0 else 0.35
            th = lerpf(th, a_th, air)
            flex = lerpf(flex, a_fl, air)
            # landing squat
            th += squat * 1.2
            flex += squat * 2.3
            thigh[i].rotation.x = th
            knee[i].rotation.x = -flex
            foot[i].rotation.x = (flex - th) * 0.6
            uarm[i].rotation.x = lerpf(arm_s, -0.7, air)
            uarm[i].rotation.z = side * (0.07 + 0.05 * run_t + 0.5 * air) + sin(t * 1.4 + side) * 0.01 * (1.0 - amp)
            farm[i].rotation.x = 0.18 + (0.25 + 0.8 * run_t) * amp + 0.3 * air

        var bob := 0.025 * amp * cos(2.0 * phase) - 0.03 * amp - squat * 0.35
        pelvis.position.y = base_y + bob
        pelvis.rotation.y = -sp0 * 0.1 * amp
        spine.rotation.x = -(lean_fwd + squat * 0.5)
        spine.rotation.y = sp0 * 0.2 * amp
        spine.rotation.z = lean_side + sin(phase) * 0.03 * amp
        spine.scale = Vector3(1.0, 1.0 + 0.012 * sin(t * 1.7), 1.0)
        neck.rotation.x = lean_fwd * 0.75
        neck.rotation.y = -spine.rotation.y * 0.8 - pelvis.rotation.y
        neck.rotation.z = -spine.rotation.z * 0.8

        # swimming: lie flat, kick the legs, crawl with the arms
        model.rotation.x = -swim * 1.3
        if swim > 0.02:
            swim_ph += delta * (2.2 + speed * 2.6)
            for i in 2:
                var sp := swim_ph * 2.0 + (PI if i == 1 else 0.0)
                thigh[i].rotation.x = lerpf(thigh[i].rotation.x, sin(sp * 1.5) * 0.35, swim)
                knee[i].rotation.x = lerpf(knee[i].rotation.x, -0.15 - maxf(0.0, sin(sp * 1.5 + 1.0)) * 0.3, swim)
                foot[i].rotation.x = lerpf(foot[i].rotation.x, 0.3, swim)
                uarm[i].rotation.x = lerpf(uarm[i].rotation.x, sp - PI * 0.5, swim)
                farm[i].rotation.x = lerpf(farm[i].rotation.x, 0.35, swim)
            spine.rotation.x = lerpf(spine.rotation.x, 0.0, swim)
            spine.rotation.z = lerpf(spine.rotation.z, sin(swim_ph * 2.0) * 0.08, swim)
            neck.rotation.x = lerpf(neck.rotation.x, 1.0, swim)
            var sw := int(floor(swim_ph * 2.0 / PI))
            if sw != last_sw:
                last_sw = sw
                if swim > 0.6 and speed > 0.4 and step_cb.is_valid() and sw % 2 == 0:
                    step_cb.call(2.5)
        _gesture(delta)


    func _gesture(delta: float) -> void:
        gb = move_toward(gb, 1.0 if (gest > 0 and not swimming) else 0.0, delta * 4.0)
        if gest > 0:
            gest_t += delta
        if gb < 0.01:
            model.position.y = 0.0
            return
        var tt := gest_t
        var ux := [uarm[0].rotation.x, uarm[1].rotation.x]
        var uz := [uarm[0].rotation.z, uarm[1].rotation.z]
        var fx := [farm[0].rotation.x, farm[1].rotation.x]
        var th := [thigh[0].rotation.x, thigh[1].rotation.x]
        var kn := [knee[0].rotation.x, knee[1].rotation.x]
        var sx := spine.rotation.x
        var sz := spine.rotation.z
        var sy := spine.rotation.y
        var nx := neck.rotation.x
        var nz := neck.rotation.z
        var py := pelvis.position.y
        var pry := pelvis.rotation.y
        var lie := 0.0
        var legs := false
        var g := gest if gest > 0 else 0
        var eas := clampf(tt * 3.0, 0.0, 1.0)
        match g:
            1:  # wave
                ux[1] = -0.2
                uz[1] = 2.4
                fx[1] = 0.5 + 0.55 * sin(tt * 11.0)
                nz = 0.08
            2:  # dance
                legs = true
                var b := sin(tt * 6.0)
                py = base_y - 0.05 - absf(b) * 0.07
                pry = sin(tt * 3.0) * 0.45
                sy = -pry * 0.6
                for i in 2:
                    var ph := tt * 6.0 + (PI if i == 1 else 0.0)
                    var side := -1.0 if i == 0 else 1.0
                    ux[i] = -1.7 + sin(ph) * 0.9
                    uz[i] = side * (0.9 + 0.3 * sin(ph))
                    fx[i] = 1.0
                    th[i] = sin(ph) * 0.35
                    kn[i] = -0.25 - maxf(0.0, sin(ph)) * 0.5
            3:  # clap
                for i in 2:
                    var side := -1.0 if i == 0 else 1.0
                    ux[i] = -1.25
                    uz[i] = side * (0.55 - 0.35 * (0.5 + 0.5 * sin(tt * 14.0)))
                    fx[i] = 1.2
            4:  # cheer
                legs = true
                py = base_y - 0.04 - absf(sin(tt * 8.0)) * 0.05
                for i in 2:
                    var side := -1.0 if i == 0 else 1.0
                    ux[i] = -0.3
                    uz[i] = side * (2.6 + 0.2 * sin(tt * 9.0 + float(i)))
                    fx[i] = 0.3
                    th[i] = 0.0
                    kn[i] = -0.2 - absf(sin(tt * 8.0)) * 0.3
            5:  # sit
                legs = true
                py = base_y - 0.46
                sx = -0.1
                for i in 2:
                    th[i] = 1.45
                    kn[i] = -1.4
                    ux[i] = -0.55
                    fx[i] = 0.7
            6:  # bow
                var d := sin(clampf(tt / 2.2, 0.0, 1.0) * PI)
                sx = -1.15 * d
                nx = 0.35 * d
            7:  # swing
                var p := clampf(tt / 1.0, 0.0, 1.0)
                ux[1] = lerpf(-2.7, 0.2, p * p)
                uz[1] = 0.3
                fx[1] = 0.5
                sy = lerpf(0.5, -0.6, p)
            8:  # throw
                var p := clampf(tt / 0.9, 0.0, 1.0)
                ux[1] = lerpf(0.9, -2.5, clampf(p * 1.8, 0.0, 1.0)) if p < 0.55 else lerpf(-2.5, 0.4, (p - 0.55) / 0.45)
                fx[1] = 0.4
                sy = lerpf(0.6, -0.5, clampf(p * 1.5, 0.0, 1.0))
            9:  # eat
                ux[1] = -1.05
                uz[1] = 0.15
                fx[1] = 2.0 + 0.2 * sin(tt * 9.0)
                nx = 0.15 + 0.08 * sin(tt * 9.0)
            10:  # give
                for i in 2:
                    ux[i] = -1.45
                    fx[i] = 0.25
                sx = -0.15
            11:  # point
                ux[1] = -1.55
                uz[1] = 0.1
                fx[1] = 0.05
            12:  # salute
                ux[1] = -1.2
                uz[1] = 0.8
                fx[1] = 2.4
            13:  # shrug
                for i in 2:
                    var side := -1.0 if i == 0 else 1.0
                    uz[i] = side * 0.7
                    ux[i] = -0.3
                    fx[i] = 1.5
                nz = 0.18 * sin(tt * 4.0)
                nx = -0.1
            14:  # flex
                for i in 2:
                    var side := -1.0 if i == 0 else 1.0
                    uz[i] = side * 1.75
                    ux[i] = 0.0
                    fx[i] = 2.3 + 0.15 * sin(tt * 6.0)
                sx = 0.12
            15:  # pet
                legs = true
                py = base_y - 0.28
                sx = -0.5
                for i in 2:
                    th[i] = 1.0
                    kn[i] = -1.6
                ux[1] = -1.0 + 0.2 * sin(tt * 5.0)
                fx[1] = 0.5
                ux[0] = -0.6
                fx[0] = 0.6
            16:  # drink
                ux[1] = -1.0
                uz[1] = 0.15
                fx[1] = 2.2
                nx = -0.45
            17:  # cast
                var p := clampf(tt / 0.5, 0.0, 1.0)
                ux[1] = lerpf(-0.2, -2.1, p) if tt < 0.5 else -1.25
                ux[0] = -0.9
                fx[0] = 0.8
                fx[1] = 0.5
                sx = 0.08 - 0.15 * p
            18:  # cook / stir
                for i in 2:
                    ux[i] = -0.95
                    fx[i] = 1.0
                uz[1] = 0.15 + 0.2 * sin(tt * 6.0)
                sx = -0.3
                nx = 0.3
            19:  # stretch
                for i in 2:
                    var side := -1.0 if i == 0 else 1.0
                    ux[i] = -3.0
                    uz[i] = side * 0.35
                    fx[i] = 0.1
                sx = 0.22 * eas
                nx = -0.25
            20:  # laugh
                for i in 2:
                    ux[i] = -0.6
                    fx[i] = 1.5
                sx = -0.1 + 0.18 * sin(tt * 14.0)
                py = base_y - 0.02 - absf(sin(tt * 14.0)) * 0.02
                nx = -0.25
            21:  # thumbs up
                ux[1] = -1.15
                uz[1] = 0.3
                fx[1] = 1.2
                nz = 0.08
            22:  # sleep
                lie = 1.0
                for i in 2:
                    ux[i] = 0.0
                    fx[i] = 0.3
            23:  # think
                ux[1] = -1.0
                fx[1] = 2.35
                ux[0] = -0.85
                fx[0] = 1.6
                nz = 0.18
                nx = 0.1
            24:  # spin
                for i in 2:
                    var side := -1.0 if i == 0 else 1.0
                    uz[i] = side * 1.45
                    ux[i] = 0.0
                    fx[i] = 0.1
                if not is_remote:
                    model.rotation.y += delta * TAU / 1.4
            25:  # fist pump
                var pump := absf(sin(tt * 7.0))
                ux[1] = -2.2 - 0.3 * pump
                uz[1] = 0.25
                fx[1] = 1.8
                py = base_y - 0.03 * pump
        var k := gb
        for i in 2:
            uarm[i].rotation.x = lerpf(uarm[i].rotation.x, ux[i], k)
            uarm[i].rotation.z = lerpf(uarm[i].rotation.z, uz[i], k)
            farm[i].rotation.x = lerpf(farm[i].rotation.x, fx[i], k)
            if legs:
                thigh[i].rotation.x = lerpf(thigh[i].rotation.x, th[i], k)
                knee[i].rotation.x = lerpf(knee[i].rotation.x, kn[i], k)
                foot[i].rotation.x = lerpf(foot[i].rotation.x, (-float(kn[i]) - float(th[i])) * 0.5, k)
        spine.rotation.x = lerpf(spine.rotation.x, sx, k)
        spine.rotation.y = lerpf(spine.rotation.y, sy, k)
        spine.rotation.z = lerpf(spine.rotation.z, sz, k)
        neck.rotation.x = lerpf(neck.rotation.x, nx, k)
        neck.rotation.z = lerpf(neck.rotation.z, nz, k)
        pelvis.position.y = lerpf(pelvis.position.y, py, k)
        pelvis.rotation.y = lerpf(pelvis.rotation.y, pry, k)
        if lie > 0.0:
            model.rotation.x = lerpf(model.rotation.x, 1.45, k)
            model.position.y = lerpf(model.position.y, 0.12, k)
        else:
            model.position.y = lerpf(model.position.y, 0.0, clampf(delta * 6.0, 0.0, 1.0))



class Hud extends Control:
    # Touch controls drawn on screen: left stick, look area, Jump and Run buttons.

    var main = null


    func _draw() -> void:
        if main == null:
            return
        var font := ThemeDB.fallback_font
        var s := get_viewport_rect().size
        var base: Vector2 = main.stick_origin if main.stick_id != -1 else Vector2(130, s.y - 120)
        var knob: Vector2 = base + main.stick_vec * 70.0
        draw_circle(base, 78.0, Color(1, 1, 1, 0.10))
        draw_arc(base, 78.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
        draw_circle(knob, 34.0, Color(1, 1, 1, 0.35))

        var jc: Vector2 = main.jump_center()
        draw_circle(jc, 58.0, Color(1, 1, 1, 0.16))
        draw_arc(jc, 58.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 2.0)
        draw_string(font, jc + Vector2(-26, 8), "JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))

        var rc: Vector2 = main.run_center()
        var on: bool = main.run_toggle
        draw_circle(rc, 44.0, Color(1.0, 0.8, 0.4, 0.45) if on else Color(1, 1, 1, 0.14))
        draw_arc(rc, 44.0, 0.0, TAU, 32, Color(1, 1, 1, 0.45), 2.0)
        draw_string(font, rc + Vector2(-21, 7), "RUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))

        var gc: Vector2 = main.gest_center()
        draw_circle(gc, 44.0, Color(0.5, 0.8, 1.0, 0.40) if main.gest_open else Color(1, 1, 1, 0.14))
        draw_arc(gc, 44.0, 0.0, TAU, 32, Color(1, 1, 1, 0.45), 2.0)
        draw_string(font, gc + Vector2(-35, 6), "GESTURE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

        var u: float = main.ui_scale()
        var sr: Rect2 = main.style_rect()
        draw_rect(sr, Color(0, 0, 0, 0.45), true)
        draw_rect(sr, Color(1, 1, 1, 0.6), false, 2.0)
        draw_string(font, sr.position + Vector2(16.0 * u, 30.0 * u), "STYLE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22.0 * u), Color(1, 1, 1, 0.95))
        if main.map_tex != null and not main.menu_open:
            if main.map_open:
                _draw_full_map(font, s)
            else:
                _draw_minimap(font, u)
        if main.menu_open:
            _draw_menu(font, s, u)
        if main.gest_open:
            _draw_gest(font, s, u)

        var t: float = main.time_of_day
        var hrs := int(t * 24.0)
        var mins := int(fmod(t * 24.0, 1.0) * 60.0)
        var label := "%02d:%02d   %d fps   Left: move  Right: look  (WASD / Shift / Space / Q E on keyboard)" % [hrs, mins, Engine.get_frames_per_second()]
        draw_string(font, Vector2(16, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))


    func _player_dir() -> Vector2:
        var m = main.player.get("model")
        var r := 0.0
        if m != null:
            r = float(m.rotation.y)
        return Vector2(-sin(r), -cos(r))


    func _arrow(c: Vector2, d: Vector2, sz: float) -> void:
        var side := Vector2(-d.y, d.x)
        var pts := PackedVector2Array([c + d * sz, c - d * sz * 0.7 + side * sz * 0.65, c - d * sz * 0.35, c - d * sz * 0.7 - side * sz * 0.65])
        draw_colored_polygon(pts, Color(1.0, 0.95, 0.3))
        var ol := PackedVector2Array(pts)
        ol.append(pts[0])
        draw_polyline(ol, Color(0, 0, 0, 0.85), 2.0)


    func _draw_minimap(font: Font, u: float) -> void:
        var r: Rect2 = main.mini_rect()
        var n: float = float(main.map_res())
        var ws: float = main.world_size()
        var span := 140.0 * (n / ws)     # pixels of map shown (140 m)
        var pp: Vector3 = main.player.global_position
        var px := (pp.x + ws * 0.5) / ws * n
        var pz := (pp.z + ws * 0.5) / ws * n
        var ox := clampf(px - span * 0.5, 0.0, n - span)
        var oz := clampf(pz - span * 0.5, 0.0, n - span)
        draw_rect(r.grow(4.0), Color(0, 0, 0, 0.55), true)
        draw_texture_rect_region(main.map_tex, r, Rect2(ox, oz, span, span))
        draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)
        var c := r.position + Vector2((px - ox) / span, (pz - oz) / span) * r.size
        _arrow(c, _player_dir(), 11.0 * u)
        draw_string(font, r.position + Vector2(r.size.x * 0.5 - 6.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * u), Color(1, 1, 1, 0.95))
        draw_string(font, r.position + Vector2(6.0, r.size.y - 8.0), "tap = map", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * u), Color(1, 1, 1, 0.8))


    func _draw_full_map(font: Font, s: Vector2) -> void:
        draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72), true)
        var r: Rect2 = main.full_map_rect()
        draw_rect(r.grow(6.0), Color(0.93, 0.88, 0.74), true)
        draw_texture_rect(main.map_tex, r, false)
        var sz: float = float(main.world_size())
        for k in range(1, 4):
            var f := k * 100.0 + 10.0
            var gx := r.position.x + (f / sz) * r.size.x
            var gy := r.position.y + (f / sz) * r.size.y
            draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.14), 1.0)
            draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(1, 1, 1, 0.14), 1.0)
        for mk in main.map_marks:
            var mp: Vector2 = mk["p"]
            var q := r.position + Vector2((mp.x + sz * 0.5) / sz, (mp.y + sz * 0.5) / sz) * r.size
            draw_circle(q, 7.0, Color(0.9, 0.25, 0.2))
            draw_arc(q, 7.0, 0.0, TAU, 16, Color(1, 1, 1), 2.0)
            draw_string(font, q + Vector2(10, 5), String(mk["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
        var pp: Vector3 = main.player.global_position
        var c := r.position + Vector2((pp.x + sz * 0.5) / sz, (pp.z + sz * 0.5) / sz) * r.size
        _arrow(c, _player_dir(), 16.0)
        draw_string(font, Vector2(r.position.x + r.size.x * 0.5 - 8.0, r.position.y - 10.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1))
        var bar := r.size.x * (100.0 / sz)
        var by := r.end.y - 18.0
        draw_line(Vector2(r.position.x + 14, by), Vector2(r.position.x + 14 + bar, by), Color(1, 1, 1), 3.0)
        draw_string(font, Vector2(r.position.x + 18 + bar, by + 6.0), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
        draw_string(font, Vector2(r.position.x + 14, r.position.y + 28.0), "Tap anywhere to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))


    func _draw_gest(font: Font, s: Vector2, u: float) -> void:
        var items: Array = main.gest_items()
        for it in items:
            var r: Rect2 = it["rect"]
            var id: int = it["id"]
            if id == -2:
                draw_rect(r, Color(0.05, 0.06, 0.08, 0.88), true)
                draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
                draw_string(font, r.position + Vector2(20.0 * u, 38.0 * u), "GESTURES  (tap one)", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * u), Color(1, 1, 1, 0.95))
            elif id == -1:
                draw_rect(r, Color(0.45, 0.25, 0.25, 0.95), true)
                draw_string(font, r.position + Vector2(24.0 * u, 29.0 * u), it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * u), Color(1, 1, 1, 1))
            else:
                draw_rect(r, Color(1, 1, 1, 0.14), true)
                draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
                draw_string(font, r.position + Vector2(14.0 * u, 32.0 * u), it["text"], HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x - 20.0 * u), int(20.0 * u), Color(1, 1, 1, 0.95))


    func _draw_menu(font: Font, s: Vector2, u: float) -> void:
        var pw := minf(s.x - 24.0, 880.0 * u)
        var x0 := (s.x - pw) * 0.5
        var panel := Rect2(x0, 20.0 * u, pw, 60.0 * u + 56.0 * u + 52.0 * u * float(main.LOOK_ROWS.size()) + 24.0 * u)
        draw_rect(panel, Color(0.05, 0.06, 0.08, 0.88), true)
        draw_rect(panel, Color(1, 1, 1, 0.5), false, 2.0)
        draw_string(font, Vector2(x0 + 20.0 * u, 20.0 * u + 38.0 * u), "CUSTOMISE CHARACTER", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * u), Color(1, 1, 1, 0.95))
        var yy := 20.0 * u + 60.0 * u
        draw_string(font, Vector2(x0 + 20.0 * u, yy + 30.0 * u), "Character", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * u), Color(1, 1, 1, 0.85))
        yy += 56.0 * u
        for row in main.LOOK_ROWS:
            draw_string(font, Vector2(x0 + 20.0 * u, yy + 28.0 * u), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * u), Color(1, 1, 1, 0.85))
            yy += 52.0 * u
        for it in main.menu_items():
            var r: Rect2 = it["rect"]
            var g: String = it["group"]
            var idx: int = it["idx"]
            var sel := false
            if g == "g":
                sel = int(main.look.get("g", 0)) == idx
                draw_rect(r, Color(0.25, 0.45, 0.30, 0.9) if sel else Color(1, 1, 1, 0.12), true)
                draw_string(font, r.position + Vector2(24.0 * u, 29.0 * u), it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * u), Color(1, 1, 1, 0.95))
            elif g == "done":
                draw_rect(r, Color(0.25, 0.45, 0.30, 0.95), true)
                draw_string(font, r.position + Vector2(26.0 * u, 29.0 * u), it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * u), Color(1, 1, 1, 1))
            else:
                sel = int(main.look.get(g, -1)) == idx
                if it.has("color"):
                    draw_rect(r, it["color"], true)
                else:
                    draw_rect(r, Color(0.2, 0.2, 0.22), true)
                    if idx == -1:
                        draw_string(font, r.position + Vector2(12.0 * u, 28.0 * u), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22.0 * u), Color(1, 1, 1, 0.9))
                    else:
                        draw_line(r.position + Vector2(8, 8) * u, r.end - Vector2(8, 8) * u, Color(1, 0.4, 0.4), 3.0)
                        draw_line(Vector2(r.end.x - 8.0 * u, r.position.y + 8.0 * u), Vector2(r.position.x + 8.0 * u, r.end.y - 8.0 * u), Color(1, 0.4, 0.4), 3.0)
                draw_rect(r, Color(1, 1, 1, 1.0) if sel else Color(1, 1, 1, 0.25), false, 4.0 if sel else 1.0)
        draw_string(font, Vector2(x0 + 20.0 * u, panel.end.y - 8.0 * u), "A = original colour.  Tint only affects Boy/Girl; the other rows only affect Explorer M/F.", HORIZONTAL_ALIGNMENT_LEFT, -1, int(15.0 * u), Color(1, 1, 1, 0.55))
