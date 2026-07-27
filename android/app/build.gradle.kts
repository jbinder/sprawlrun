import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of version control. See
// android/key.properties.example for the expected keys.
//
// When the file is absent — a fresh clone, or CI without secrets — release
// builds fall back to the debug key so `flutter build apk` still works. Such a
// build is fine for testing and must never be published: it carries the
// throwaway "CN=Android Debug" identity and cannot be updated later by a
// properly signed release.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

// Keep Google Play Services out of the packaged app.
//
// geolocator_android declares `play-services-location`, which is proprietary:
// it would bar the app from F-Droid and make a de-Googled ROM depend on a
// Google component. Excluding it here removes the library from *this module's*
// runtime classpath, so it never reaches the APK, while geolocator_android
// still compiles against it in its own subproject.
//
// geolocator supports this explicitly. Its client selection catches
// NoClassDefFoundError with the comment "This might happen when the GMS package
// has been excluded by the app developer due to its proprietary license", and
// falls back to the AOSP LocationManager. `forceLocationManager: true` in
// lib/services/location_service.dart means that path is never even consulted.
configurations.configureEach {
    exclude(group = "com.google.android.gms")
}

android {
    namespace = "io.github.jbinder.sprawlrun"
    compileSdk = flutter.compileSdkVersion

    // Required because path_provider_android pulls in package:jni, which
    // compiles dartjni.c through CMake. Declaring it here keeps the app module
    // on the same NDK as the plugin modules, which all use flutter.ndkVersion.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.jbinder.sprawlrun"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            // R8 is deliberately left at the Flutter Gradle Plugin's default
            // (enabled, with Flutter's own keep rules). Disabling it grows the
            // dex from ~2 MB to ~15 MB. This appends to those rules rather than
            // replacing them.
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
