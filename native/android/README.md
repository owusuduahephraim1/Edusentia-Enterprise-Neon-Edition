# Edusentia Enterprise Neon Edition for Android

This Android shell opens the live Neon Edition:

https://owusuduahephraim1.github.io/Edusentia-Enterprise-Neon-Edition/

It uses a separate Android identity from the Supabase edition so both editions can be installed independently.

- Application ID: `app.edusentia.enterprise.neon`
- Minimum Android: API 23
- Target SDK: API 35

## Build

- Internal/installable package without production signing secrets: `gradle :app:assembleDebug`
- Production signed package when long-lived signing secrets are configured: `gradle :app:assembleRelease`

For public distribution, preserve one long-lived Android signing identity. Do not commit the keystore.


## Automatic Android updates

The Android shell integrates Google Play In-App Updates using `com.google.android.play:app-update:2.1.0`. A Play-installed production build checks for an available update at launch and requests the immediate update flow; interrupted updates are resumed when the app returns to the foreground.

Android requires the permanent application signing identity to remain stable for upgrades. Direct/sideloaded builds do not receive Google Play automatic updates. They can still be replaced by a newer APK signed with the same permanent key, subject to Android's normal installation approval.
