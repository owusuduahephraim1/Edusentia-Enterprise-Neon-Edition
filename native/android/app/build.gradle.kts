plugins { id("com.android.application") }

val releaseStore = System.getenv("EDUSENTIA_NEON_ANDROID_KEYSTORE")
val releaseStorePassword = System.getenv("EDUSENTIA_NEON_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("EDUSENTIA_NEON_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("EDUSENTIA_NEON_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = !releaseStore.isNullOrBlank() && !releaseStorePassword.isNullOrBlank() && !releaseKeyAlias.isNullOrBlank() && !releaseKeyPassword.isNullOrBlank()

android {
  namespace = "app.edusentia.enterprise.neon"
  compileSdk = 35
  defaultConfig {
    applicationId = "app.edusentia.enterprise.neon"
    minSdk = 23
    targetSdk = 35
    versionCode = 704001
    versionName = "7.4.0-neon-r42"
  }
  signingConfigs {
    if (hasReleaseSigning) {
      create("edusentiaNeonRelease") {
        storeFile = file(releaseStore!!)
        storePassword = releaseStorePassword
        keyAlias = releaseKeyAlias
        keyPassword = releaseKeyPassword
      }
    }
  }
  buildTypes {
    release {
      isMinifyEnabled = false
      if (hasReleaseSigning) signingConfig = signingConfigs.getByName("edusentiaNeonRelease")
    }
  }
}

dependencies {
}
