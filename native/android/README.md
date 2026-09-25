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
