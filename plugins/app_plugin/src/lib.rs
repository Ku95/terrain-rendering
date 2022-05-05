mod camera;
mod parse;

use crate::camera::{setup_camera, toggle_camera_system};
use bevy::{
    diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin},
    pbr::{
        wireframe::{Wireframe, WireframePlugin},
        Clusters, VisiblePointLights,
    },
    prelude::*,
    render::{primitives::Frustum, view::VisibleEntities},
    utils::HashSet,
};
use bevy_fly_camera::{FlyCamera, FlyCameraPlugin};

use bevy_terrain::render::attachments::{
    add_albedo_attachment_config, add_height_attachment_config,
};
use bevy_terrain::{
    bundles::TerrainBundle, config::TerrainConfig, node_atlas::NodeAtlas, quadtree::Quadtree,
    TerrainPlugin,
};
use std::{any::TypeId, time::Duration};

/// A plugin, which sets up the testing application.
pub struct AppPlugin;

impl Plugin for AppPlugin {
    fn build(&self, app: &mut App) {
        // enable asset hot reloading
        app.world
            .resource::<AssetServer>()
            .watch_for_changes()
            .unwrap();

        let mut ignore_components: HashSet<TypeId> = HashSet::default();
        ignore_components.insert(TypeId::of::<Camera>());
        ignore_components.insert(TypeId::of::<GlobalTransform>());
        ignore_components.insert(TypeId::of::<VisibleEntities>());
        ignore_components.insert(TypeId::of::<Frustum>());
        ignore_components.insert(TypeId::of::<Clusters>());
        ignore_components.insert(TypeId::of::<VisiblePointLights>());
        ignore_components.insert(TypeId::of::<PreviousParent>());
        ignore_components.insert(TypeId::of::<FlyCamera>());

        ignore_components.insert(TypeId::of::<Quadtree>());
        ignore_components.insert(TypeId::of::<NodeAtlas>());

        app.insert_resource(Msaa { samples: 4 })
            // .insert_resource(WorldInspectorParams {
            //     despawnable_entities: true,
            //     ignore_components,
            //     ..default()
            // })
            // .add_plugin(WorldInspectorPlugin::new())
            .add_plugin(WireframePlugin)
            .add_plugin(LogDiagnosticsPlugin {
                debug: false,
                wait_duration: Duration::from_secs(5),
                filter: None,
            })
            .add_plugin(FrameTimeDiagnosticsPlugin)
            .add_plugin(FlyCameraPlugin)
            .add_plugin(TerrainPlugin)
            .add_startup_system(setup_scene)
            .add_startup_system(setup_camera)
            .add_system(toggle_camera_system)
            .add_system(toggle_wireframe_system);
    }
}

fn setup_scene(mut commands: Commands) {
    let mut config = TerrainConfig::new(128, 5, UVec2::new(2, 2), 1.0, 1000.0, 2048);

    add_height_attachment_config(&mut config, 129);
    add_albedo_attachment_config(&mut config, 128 * 5);

    // let path = "assets/heightmaps/Hartenstein.png";
    // parse::process_height(path, 2);
    // bevy_terrain::preprocess::generate_node_textures(&config, path, "assets/output/height");

    //let path = "assets/heightmaps/test.png";
    // parse::process_albedo(path, 2);
    //bevy_terrain::preprocess::generate_albedo_textures(&config, path, "assets/output/albedo");

    // let path = "assets/heightmaps/Hartenstein_albedo.png";
    // parse::process_albedo(path, 2);
    // bevy_terrain::preprocess::generate_albedo_textures(&config, path, "assets/output/albedo");

    // bevy_terrain::preprocess::generate_node_textures(
    //     &config,
    //     "assets/heightmaps/heightmap.png",
    //     "assets/output/",
    // );

    commands
        .spawn_bundle(TerrainBundle::new(config))
        .insert(Wireframe);
}

fn toggle_wireframe_system(
    mut commands: Commands,
    input: Res<Input<KeyCode>>,
    terrain_query: Query<(Entity, Option<&Wireframe>), With<TerrainConfig>>,
) {
    if input.just_pressed(KeyCode::W) {
        for (entity, wireframe) in terrain_query.iter() {
            match wireframe {
                None => commands.entity(entity).insert(Wireframe),
                Some(_) => commands.entity(entity).remove::<Wireframe>(),
            };
        }
    }
}
