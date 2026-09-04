import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives in android/key.properties, which is gitignored.
// See android/key.properties.example for the expected keys.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

// Escape hatch for `flutter run --release` on a dev machine that has no keystore.
// Must be passed explicitly, so a debug-signed artifact can never be produced by
// accident: ./gradlew assembleRelease -PallowDebugSigning=true
val allowDebugSigning = (project.findProperty("allowDebugSigning") as String?) == "true"

android {
    // Matches the registered Android application in Firebase project midoctor-3dbdb.
    // Android application IDs are immutable once published to Play.
    namespace = "midoctor.in"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "midoctor.in"
        // firebase_auth requires 23; 24 is the practical floor and covers >99% of
        // the Indian Android install base.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // NOTE: this block is evaluated during Gradle's configuration phase for
            // EVERY task, including assembleDebug. Never throw from here — the
            // missing-keystore check lives in the taskGraph hook below so that
            // debug builds keep working on machines with no signing material.
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                // Deliberately unsigned. The taskGraph guard fails the build before
                // this can produce an artifact.
                else -> null
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Fail only when a release artifact is actually being assembled, so that a
// missing keystore never silently yields a debug-signed or unsigned release,
// while `assembleDebug` remains unaffected.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        task.name.contains("Release") &&
            listOf("assemble", "bundle", "package", "install").any { task.name.startsWith(it) }
    }
    if (buildingRelease && !hasReleaseSigning && !allowDebugSigning) {
        throw GradleException(
            "No release signing config found.\n" +
                "Create android/key.properties (see key.properties.example), " +
                "or pass -PallowDebugSigning=true for a local-only build."
        )
    }
    if (buildingRelease && !hasReleaseSigning && allowDebugSigning) {
        logger.warn(
            "WARNING: signing release build with the DEBUG keystore because " +
                "-PallowDebugSigning=true was passed. Never distribute this artifact."
        )
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
