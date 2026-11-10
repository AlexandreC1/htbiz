import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// The Maps key was hard-coded in AndroidManifest.xml, so it was committed and
// publicly readable. It is injected as a manifest placeholder instead, read
// from local.properties (already gitignored) or from the GOOGLE_MAPS_API_KEY
// environment variable in CI.
//
// Note this only keeps the key out of the repository — it still ships in the
// built APK. The protection that matters is restricting the key to this app's
// package name and SHA-1 in the Google Cloud console.
val mapsApiKey: String = run {
    val props = Properties()
    val propsFile = rootProject.file("local.properties")
    if (propsFile.exists()) {
        propsFile.inputStream().use { props.load(it) }
    }
    props.getProperty("GOOGLE_MAPS_API_KEY")
        ?: System.getenv("GOOGLE_MAPS_API_KEY")
        ?: ""
}

// Release signing reads android/key.properties (gitignored, see
// key.properties.example). Without that file (CI, fresh clones) the release
// build falls back to the debug keystore so `flutter run --release` and
// `flutter build appbundle` still work, but Google Play rejects that bundle.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else {
    logger.warn(
        "WARNING: android/key.properties not found. The release build is " +
            "signed with the DEBUG key and is NOT uploadable to Google Play. " +
            "See android/key.properties.example."
    )
}

android {
    namespace = "com.htbiz.htbiz"
    // Google Play requires API 36. maxOf keeps a newer Flutter default.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_11
        }
    }

    defaultConfig {
        applicationId = "com.htbiz.htbiz"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["googleMapsApiKey"] = mapsApiKey
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug"
            )
        }
    }
}

flutter {
    source = "../.."
}
