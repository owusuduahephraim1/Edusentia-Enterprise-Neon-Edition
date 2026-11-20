fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new()
            .app_manifest(tauri_build::AppManifest::new().commands(&["save_document"])),
    ).expect("Unable to build the Edusentia Tauri application permissions");
}
