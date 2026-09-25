# Neon native signing and update continuity

The Neon Edition intentionally has signing identities separate from the Supabase edition.

## Required GitHub repository secrets

Windows updater:
- EDUSENTIA_NEON_TAURI_SIGNING_PRIVATE_KEY
- EDUSENTIA_NEON_TAURI_SIGNING_PRIVATE_KEY_PASSWORD
- EDUSENTIA_NEON_TAURI_UPDATER_PUBLIC_KEY

Android production identity:
- EDUSENTIA_NEON_ANDROID_KEYSTORE_BASE64
- EDUSENTIA_NEON_ANDROID_KEYSTORE_PASSWORD
- EDUSENTIA_NEON_ANDROID_KEY_ALIAS
- EDUSENTIA_NEON_ANDROID_KEY_PASSWORD

Never commit the private updater key, Android keystore, or their passwords.

## Release behavior

The normal native installer workflow continues to build test/install packages. The signed publication workflow only publishes when all permanent signing secrets exist.

Once configured, a change under `native/**` triggers a new signed native release:

1. Windows MSI/NSIS are generated with Tauri updater signatures.
2. `latest.json` is published in the GitHub Release for automatic Windows updater discovery.
3. Android APK and AAB are generated with the permanent Neon Android key.
4. Play-installed Android builds use the Google Play immediate in-app update flow.
5. All release files receive SHA-256 checksum manifests.

Normal web application changes do not need a native release because the Windows and Android shells load the continuously synchronized hosted Neon application.

## Important first production transition

The currently shared test APK is debug-signed. A permanent production-signed APK cannot update that debug package in place. Test installations must be uninstalled once before installing the first permanent production-signed Neon APK. From that point forward, keeping the same permanent Android signing identity allows normal upgrades.
