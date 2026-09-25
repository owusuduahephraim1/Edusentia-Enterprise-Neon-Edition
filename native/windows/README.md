# Edusentia Enterprise Neon Edition for Windows

This Tauri 2 desktop shell packages the live Neon Edition at:

https://owusuduahephraim1.github.io/Edusentia-Enterprise-Neon-Edition/

It is intentionally a separate native identity from the Supabase edition.

## Installer formats

`npm install && npm run build` produces:

- Windows Installer (.msi)
- NSIS Setup (.exe)

The installer uses Microsoft WebView2. Hosted application updates continue through the Neon Edition GitHub Pages/PWA consistency mechanism, so the Windows installer only needs to change when the native shell itself changes.

## Identity

- Product: Edusentia Enterprise Neon Edition
- Windows identifier: app.edusentia.enterprise.neon
- Application data/install identity is separate from the Supabase native package.

## Signing

Unsigned MSI/EXE packages are suitable for internal installation/testing but Windows may show a SmartScreen warning. For public distribution, sign the executable and installers with a long-lived Authenticode certificate and preserve that identity for future updates.


## Automatic native-shell updates

Production-signed Windows releases use the Tauri v2 updater. A release build checks the repository's latest `latest.json`, verifies the downloaded installer with the permanent Tauri updater public key, downloads the update, and installs it in passive mode. The private updater key never belongs in the repository.

The first updater-enabled build must be installed once. After that, later signed native Windows releases can update the installed application automatically.
