plugins {
    id("com.android.application")
}

// Host the PWA is served from. Override in CI or for local builds with:
//   ./gradlew assembleRelease -PpantriaHost=pantria.example.com
val pantriaHost: String = (project.findProperty("pantriaHost") as String?) ?: "pantria.example.com"
val pantriaUrl: String = "https://$pantriaHost"

android {
    namespace  = "de.lunawolf.pantria"
    compileSdk = 35

    defaultConfig {
        applicationId = "de.lunawolf.pantria"
        minSdk        = 23   // androidbrowserhelper minimum
        targetSdk     = 35
        versionCode   = 1
        versionName   = "1.0"

        // Surfaced into strings.xml via resValue so AndroidManifest can
        // reference them by @string/... -- the host shows in the splash
        // screen / install dialog, the URL is read by LauncherActivity.
        resValue("string", "pantria_host", pantriaHost)
        resValue("string", "pantria_url",  pantriaUrl)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            // The debug keystore signs release builds by default so a
            // fresh checkout produces a working APK without configuring
            // signing. For Play Store distribution, swap this for a
            // proper release keystore (see android/README.md).
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // androidbrowserhelper provides LauncherActivity -- a turnkey TWA
    // entry point that opens a Trusted Web Activity for the configured
    // URL, handles asset-link verification, and falls back to Custom
    // Tabs when no compatible browser is available.
    implementation("com.google.androidbrowserhelper:androidbrowserhelper:2.6.0")
}
