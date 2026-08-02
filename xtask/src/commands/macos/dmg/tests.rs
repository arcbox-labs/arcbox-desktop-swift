use super::{
    BundleProfile, boot_asset_files, boot_cache_ready, embed_boot_assets, local_boot_cache_ready,
    prepare_strip_copy, should_reuse_local_boot_cache, write_binaries_fragment,
};

#[test]
fn failed_strip_preparation_leaves_no_temporary_file() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("binary");
    std::fs::create_dir(&source).unwrap();

    assert!(prepare_strip_copy(&source).is_err());

    let entries = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect::<Vec<_>>();
    assert_eq!(entries, ["binary"]);
}

#[test]
fn boot_cache_ignores_legacy_runtime_image() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join("manifest.json"),
        r#"{"targets":{"arm64":{"kernel":{},"rootfs":{},"runtime":{}}}}"#,
    )
    .unwrap();
    for name in ["kernel", "rootfs.erofs"] {
        std::fs::write(dir.path().join(name), name).unwrap();
    }

    assert_eq!(
        boot_asset_files(&dir.path().join("manifest.json")).unwrap(),
        ["manifest.json", "kernel", "rootfs.erofs"]
    );
    assert!(boot_cache_ready(dir.path()));
}

#[test]
fn local_boot_cache_keeps_the_runtime_manifest_fragment() {
    let dir = tempfile::tempdir().unwrap();
    let manifest = dir.path().join("manifest.json");
    std::fs::write(
        &manifest,
        r#"{
            "source_repo": "local/boot-assets",
            "targets": {"arm64": {"kernel": {}, "rootfs": {}}},
            "binaries": [{
                "name": "dockerd",
                "targets": {"arm64": {"path": "dockerd", "sha256": "00"}}
            }]
        }"#,
    )
    .unwrap();
    for name in ["kernel", "rootfs.erofs"] {
        std::fs::write(dir.path().join(name), name).unwrap();
    }

    assert!(local_boot_cache_ready(dir.path()));
    assert!(should_reuse_local_boot_cache(
        BundleProfile::Development,
        false,
        dir.path()
    ));
    assert!(!should_reuse_local_boot_cache(
        BundleProfile::Production,
        false,
        dir.path()
    ));
    let fragment = dir.path().join("binaries.json");
    write_binaries_fragment(&manifest, &fragment).unwrap();
    let binaries: serde_json::Value =
        serde_json::from_reader(std::fs::File::open(fragment).unwrap()).unwrap();
    assert_eq!(binaries[0]["name"], "dockerd");
}

#[test]
fn embedded_boot_assets_replace_stale_assets_without_runtime_image() {
    let dir = tempfile::tempdir().unwrap();
    let app = dir.path().join("ArcBox.app");
    let resources = app.join("Contents").join("Resources");
    std::fs::create_dir_all(resources.join("assets").join("old")).unwrap();
    std::fs::write(
        resources.join("assets").join("old").join("runtime.erofs"),
        "stale runtime",
    )
    .unwrap();

    let arcbox = dir.path().join("arcbox");
    std::fs::create_dir_all(&arcbox).unwrap();
    std::fs::write(arcbox.join("assets.lock"), "[boot]\nversion = \"test\"\n").unwrap();
    let cache = arcbox.join("target").join("boot-assets").join("test");
    std::fs::create_dir_all(&cache).unwrap();
    std::fs::write(
        cache.join("manifest.json"),
        r#"{"targets":{"arm64":{"kernel":{},"rootfs":{},"runtime":{}}}}"#,
    )
    .unwrap();
    for name in ["kernel", "rootfs.erofs", "runtime.erofs"] {
        std::fs::write(cache.join(name), name).unwrap();
    }

    embed_boot_assets(&app, &arcbox, BundleProfile::Production).unwrap();

    let embedded = resources.join("assets").join("test");
    for name in ["manifest.json", "kernel", "rootfs.erofs"] {
        assert!(embedded.join(name).is_file());
    }
    assert!(!embedded.join("runtime.erofs").exists());
    assert!(!resources.join("assets").join("old").exists());
}
