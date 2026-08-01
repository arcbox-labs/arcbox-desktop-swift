use super::{boot_asset_files, boot_cache_ready, prepare_strip_copy};

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
