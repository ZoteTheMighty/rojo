#[macro_use] extern crate lazy_static;

extern crate librojo;

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};

use rbx_tree::RbxValue;

use librojo::{
    project::{Project, ProjectNode, InstanceProjectNode, SyncPointProjectNode},
};

lazy_static! {
    static ref TEST_PROJECTS_ROOT: PathBuf = {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../test-projects")
    };
}

#[test]
fn empty() {
    let project_file_location = TEST_PROJECTS_ROOT.join("empty/roblox-project.json");
    let project = Project::load_exact(&project_file_location).unwrap();

    assert_eq!(project.name, "empty");
}

#[test]
fn empty_fuzzy_file() {
    let project_file_location = TEST_PROJECTS_ROOT.join("empty/roblox-project.json");
    let project = Project::load_fuzzy(&project_file_location).unwrap();

    assert_eq!(project.name, "empty");
}

#[test]
fn empty_fuzzy_folder() {
    let project_location = TEST_PROJECTS_ROOT.join("empty");
    let project = Project::load_fuzzy(&project_location).unwrap();

    assert_eq!(project.name, "empty");
}

#[test]
fn single_sync_point() {
    let project_file_location = TEST_PROJECTS_ROOT.join("single-sync-point/roblox-project.json");
    let project = Project::load_exact(&project_file_location).unwrap();

    let expected_project = {
        let foo = ProjectNode::SyncPoint(SyncPointProjectNode {
            path: project_file_location.parent().unwrap().join("lib"),
            children: HashMap::new(),
        });

        let mut replicated_storage_children = HashMap::new();
        replicated_storage_children.insert("Foo".to_string(), foo);

        let replicated_storage = ProjectNode::Instance(InstanceProjectNode {
            class_name: "ReplicatedStorage".to_string(),
            children: replicated_storage_children,
            properties: HashMap::new(),
            metadata: Default::default(),
        });

        let mut http_service_properties = HashMap::new();
        http_service_properties.insert("HttpEnabled".to_string(), RbxValue::Bool {
            value: true,
        });

        let http_service = ProjectNode::Instance(InstanceProjectNode {
            class_name: "HttpService".to_string(),
            children: HashMap::new(),
            properties: http_service_properties,
            metadata: Default::default(),
        });

        let mut root_children = HashMap::new();
        root_children.insert("ReplicatedStorage".to_string(), replicated_storage);
        root_children.insert("HttpService".to_string(), http_service);

        let root_node = ProjectNode::Instance(InstanceProjectNode {
            class_name: "DataModel".to_string(),
            children: root_children,
            properties: HashMap::new(),
            metadata: Default::default(),
        });

        Project {
            name: "single-sync-point".to_string(),
            tree: root_node,
            serve_port: None,
            serve_place_ids: None,
            file_location: project_file_location.clone(),
        }
    };

    assert_eq!(project, expected_project);
}

#[test]
fn test_model() {
    let project_file_location = TEST_PROJECTS_ROOT.join("test-model/roblox-project.json");
    let project = Project::load_exact(&project_file_location).unwrap();

    assert_eq!(project.name, "test-model");
}