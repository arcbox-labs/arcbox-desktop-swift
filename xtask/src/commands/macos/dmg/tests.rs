use super::{
    BundleProfile, boot_asset_files, boot_cache_ready, embed_boot_assets, prepare_strip_copy,
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
fn boot_cache_requires_declared_runtime_image() {
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
        ["manifest.json", "kernel", "rootfs.erofs", "runtime.erofs"]
    );
    assert!(!boot_cache_ready(dir.path()));

    std::fs::write(dir.path().join("runtime.erofs"), "runtime").unwrap();
    assert!(boot_cache_ready(dir.path()));
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
