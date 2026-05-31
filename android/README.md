# Pantria Android (TWA)

A [Trusted Web Activity](https://developer.chrome.com/docs/android/trusted-web-activity)
shell that opens the Pantria PWA full-screen, without browser chrome. No native
code, no separate JSON API — the Android app is the web app, signed and packaged.

When the user installs the APK they get an icon in their launcher, push-style
launch, deep-link handling (any `https://<host>/...` link opens in Pantria), and
camera access via the existing barcode-scanner page. Updates to the web app
appear immediately — the Android build only needs re-shipping when the package
metadata itself changes (host, icon, version code for Play Store).

## Prerequisites

- **JDK 17+** (`brew install openjdk@17` or use IntelliJ / Android Studio's bundled JDK)
- **Android command-line tools** (or full Android Studio)
- The PWA reachable at an **HTTPS** host — Chrome refuses TWA verification on plain HTTP

## One-time setup

1. **Generate the Gradle wrapper jar** (we don't ship it to avoid bundling a
   third-party binary):

   ```bash
   cd android
   gradle wrapper --gradle-version 8.10.2
   ```

   Now `./gradlew` works.

2. **Point the build at your host**. The default in `app/build.gradle.kts` is
   `pantria.example.com`; override it per-build:

   ```bash
   ./gradlew assembleRelease -PpantriaHost=pantria.your-domain.tld
   ```

   Or set it permanently in `gradle.properties`:

   ```properties
   pantriaHost=pantria.your-domain.tld
   ```

3. **Compute the signing-cert SHA-256** so Chrome can verify the TWA owns the
   domain. For the debug keystore that ships with the Android SDK:

   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore \
           -alias androiddebugkey -storepass android -keypass android \
       | grep 'SHA256:'
   ```

   Strip the `SHA256: ` prefix and any whitespace — you want the bare
   `AA:BB:CC:...` fingerprint.

4. **Expose the fingerprint to the Rails app** so it shows up in
   `/.well-known/assetlinks.json`. Add to your environment (`.env` / Unraid
   template / docker-compose):

   ```
   ANDROID_TWA_PACKAGE=de.lunawolf.pantria
   ANDROID_TWA_FINGERPRINTS=AA:BB:CC:...
   ```

   Restart the Rails app and verify:

   ```bash
   curl -s https://pantria.your-domain.tld/.well-known/assetlinks.json
   ```

   The JSON must contain your package name and fingerprint, exactly. Chrome
   re-fetches this on every install; mismatch = URL bar reappears.

## Build

```bash
cd android
./gradlew assembleDebug      # APK at app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease    # APK at app/build/outputs/apk/release/app-release.apk
```

The release config signs with the debug keystore by default so a fresh checkout
produces a working APK without any keystore juggling. **Do not publish that
build to the Play Store** — see "Production signing" below.

## Install on a device

USB-debug-enabled phone connected:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open the app: you should see the brand-colour splash for ~300ms, then the
Pantria login screen with no URL bar and no browser chrome.

If you see a URL bar at the top, the asset-link verification failed — open
`chrome://flags/#enable-quality-enforcing-twa` on the device, or check
`adb logcat | grep -i 'origin'` for "Failed to verify origin" messages. Usual
suspects: wrong fingerprint pasted into the env var, host typo, HTTP-not-HTTPS,
or the JSON file isn't actually being served (check the route).

## Camera permission

The first time the user hits the scan page, Chrome prompts for camera permission
*through the TWA*. The grant is scoped to the origin and persists across the
PWA + browser + TWA. The `<uses-permission android:name="android.permission.CAMERA" />`
declaration in `AndroidManifest.xml` is what allows Chrome to surface that
prompt at all — without it the prompt is silently denied.

## Production signing

Before publishing to Play Store:

1. Create a release keystore:

   ```bash
   keytool -genkey -v -keystore ~/pantria-release.jks \
           -keyalg RSA -keysize 2048 -validity 25000 \
           -alias pantria
   ```

2. Switch `app/build.gradle.kts`'s release `signingConfig` to a custom one
   pointing at that keystore (with credentials from `~/.gradle/gradle.properties`,
   never committed).

3. Re-compute the SHA-256 of the **release** cert and append it to
   `ANDROID_TWA_FINGERPRINTS` (Chrome accepts a list, so debug + release can
   coexist during the rollout). Re-deploy Rails.

4. Build an Android App Bundle for upload:

   ```bash
   ./gradlew bundleRelease
   ```

   Upload `app/build/outputs/bundle/release/app-release.aab` to Play Console.

## What's *not* in here

- No JSON API. The Rails app renders HTML; the TWA shows that HTML. If you ever
  want native Kotlin views instead, that's a different project.
- No offline data. The PWA's service worker handles "page available when
  network is down" via the offline page. Real offline editing would need a
  client-side store + sync — out of scope.
- No push notifications. Web Push works inside a TWA on Android (Chrome relays
  them), but Pantria doesn't have a push backend yet.
