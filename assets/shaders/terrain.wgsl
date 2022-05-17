// imports the View struct and the view binding, aswell as the lighting structs and bindings
#import bevy_pbr::mesh_view_bind_group
#import bevy_pbr::mesh_struct
#import bevy_terrain::config
#import bevy_terrain::patch

// vertex intput
struct Vertex {
    [[builtin(instance_index)]] instance: u32;
    [[builtin(vertex_index)]] index: u32;
};

// fragment input
struct Fragment {
    [[builtin(position)]] position: vec4<f32>;
    [[location(0)]] world_position: vec4<f32>;
    [[location(1)]] color: vec4<f32>;
};

// mesh bindings
[[group(1), binding(0)]]
var<uniform> mesh: Mesh;

// terrain data bindings
[[group(2), binding(0)]]
var<uniform> config: TerrainConfig;
[[group(2), binding(1)]]
var quadtree: texture_2d_array<u32>;
[[group(2), binding(2)]]
var filter_sampler: sampler;
[[group(2), binding(3)]]
var height_atlas: texture_2d_array<f32>;
[[group(2), binding(4)]]
var albedo_atlas: texture_2d_array<f32>;

[[group(3), binding(0)]]
var<storage> patch_list: PatchList;

#import bevy_terrain::atlas

// Todo: precompute the node sizes?
fn node_size(lod: u32) -> f32 {
    return f32(config.chunk_size * (1u << lod));
}

fn atlas_lookup(world_position: vec2<f32>) -> AtlasLookup {
    let distance = distance(world_position, view.world_position.xz);

    // Todo: replace log2
    // Log2(x) = result
    // while (x >>= 1) result++;

    let layer = clamp(u32(log2(distance / 220.0)), 0u, config.lod_count - 1u);
    // let layer = 0u;

    let map_coords =  vec2<i32>(world_position / node_size(layer)) ;
    let lookup = textureLoad(quadtree, map_coords, i32(layer), 0);

    let lod = lookup.z;
    let atlas_index =  i32((lookup.x << 8u) + lookup.y);
    let atlas_coords = (world_position / node_size(lod)) % 1.0;

    return AtlasLookup(lod, atlas_index, atlas_coords);
}

fn calculate_position(vertex_index: u32, stitch: u32) -> vec2<u32> {
    // use first and last index twice, to form degenerate triangles
    // Todo: documentation
    let row_index = clamp(vertex_index % config.vertices_per_row, 1u, config.vertices_per_row - 2u) - 1u;
    var vertex_position = vec2<u32>((row_index & 1u) + vertex_index / config.vertices_per_row, row_index >> 1u);

    // stitch the edges of the patches together
    if (vertex_position.x == 0u && (stitch & 1u) != 0u) {
        vertex_position.y = vertex_position.y & 0xFFFEu;
    }
    if (vertex_position.y == 0u && (stitch & 2u) != 0u) {
        vertex_position.x = vertex_position.x & 0xFFFEu;
    }
    if (vertex_position.x == config.patch_size && (stitch & 4u) != 0u) {
        vertex_position.y = vertex_position.y + 1u & 0xFFFEu;
    }
    if (vertex_position.y == config.patch_size && (stitch & 8u) != 0u) {
        vertex_position.x = vertex_position.x + 1u & 0xFFFEu;
    }

    return vertex_position;
}

fn calculate_normal(uv: vec2<f32>, atlas_index: i32, lod: u32) -> vec3<f32> {
    let left  = textureSampleLevel(height_atlas, filter_sampler, uv, atlas_index, 0.0, vec2<i32>(-1,  0)).x;
    let up    = textureSampleLevel(height_atlas, filter_sampler, uv, atlas_index, 0.0, vec2<i32>( 0, -1)).x;
    let right = textureSampleLevel(height_atlas, filter_sampler, uv, atlas_index, 0.0, vec2<i32>( 1,  0)).x;
    let down  = textureSampleLevel(height_atlas, filter_sampler, uv, atlas_index, 0.0, vec2<i32>( 0,  1)).x;
    let normal = normalize(vec3<f32>(right - left, 2.0 * f32(1u << lod) / config.height, down - up));

    return normal;
}

fn show_lod(lod: u32) -> vec4<f32> {
    if (lod == 0u) {
        return vec4<f32>(1.0,0.0,0.0,1.0);
    }
    if (lod == 1u) {
        return vec4<f32>(0.0,1.0,0.0,1.0);
    }
    if (lod == 2u) {
        return vec4<f32>(0.0,0.0,1.0,1.0);
    }
    if (lod == 3u) {
        return vec4<f32>(1.0,1.0,0.0,1.0);
    }
    if (lod == 4u) {
        return vec4<f32>(1.0,0.0,1.0,1.0);
    }

    return vec4<f32>(0.0);
}

fn show_patches(patch: Patch) -> vec4<f32> {
    if ((patch.x + patch.y) / config.patch_size % 2u == 0u) {
        return vec4<f32>(1.0);
    }
    else {
        return vec4<f32>(0.5);
    }
}

[[stage(vertex)]]
fn vertex(vertex: Vertex) -> Fragment {
    let patch = patch_list.data[vertex.instance];

    let vertex_position = calculate_position(vertex.index, patch.stitch);

    let world_position =
        vec2<f32>(f32(patch.x + vertex_position.x), f32(patch.y + vertex_position.y)) * f32(patch.size);

    let distance = distance(view.world_position.xz, world_position);

    let lookup = atlas_lookup(world_position);
    let lod = lookup.lod;
    let atlas_index = lookup.atlas_index;
    let atlas_coords = lookup.atlas_coords;

    var height = textureSampleLevel(height_atlas, filter_sampler, atlas_coords, atlas_index, 0.0).x;

    // discard vertecies with height 0
    if (height == 0.0) {
        height = height / 0.0;
    }

    height = config.height * height;
    let world_position = mesh.model * vec4<f32>(world_position.x, height, world_position.y, 1.0);

    var out: Fragment;
    out.position = view.view_proj * world_position;
    out.world_position = world_position;
    out.color = vec4<f32>(1.0);

    out.color = mix(out.color, show_patches(patch), 1.0);

    for (var i: u32 = 1u; i < config.lod_count; i = i + 1u) {
        let circle = (220.0 * f32(1 << i));
        let thickness = 8.0;

        if (circle - thickness < distance && distance < circle + thickness) {
            out.color = vec4<f32>(1.0, 0.0, 0.0, 1.0);
        }
    }

    // for (var i: u32 = 1u; i < config.lod_count; i = i + 1u) {
    //     let circle = f32((1u << i) * config.patch_size * 2u) * 10.0;
    //     let thickness = 8.0;
    //
    //     if (circle - thickness < distance && distance < circle + thickness) {
    //         out.color = vec4<f32>(0.0, 0.0, 1.0, 1.0);
    //     }
    // }

    return out;
}

[[stage(fragment)]]
fn fragment(fragment: Fragment) -> [[location(0)]] vec4<f32> {
    var output_color = fragment.color;

    let lookup = atlas_lookup(fragment.world_position.xz);
    let lod = lookup.lod;
    let atlas_index = lookup.atlas_index;
    let atlas_coords = lookup.atlas_coords;

    output_color = mix(output_color, show_lod(lod), 0.5);
    // output_color = mix(output_color, textureSample(albedo_atlas, filter_sampler, atlas_coords, atlas_index), 1.0);

    let lighting = true;
    // let lighting = false;

    if (lighting) {
        let ambient = 0.1;
        let light_pos = vec3<f32>(5000.0, 2000.0, 5000.0);
        let direction = normalize(light_pos - fragment.world_position.xyz);
        let normal = calculate_normal(atlas_coords, atlas_index, lod);

        let diffuse = max(dot(direction, normal), 0.0);

        output_color = output_color * (ambient + diffuse) * 1.0;
    }

    return output_color;
}
