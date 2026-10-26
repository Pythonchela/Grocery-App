import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push notifications. The Firebase plugin is applied only when a config file
// exists, so the app builds and runs without a Firebase project and push switches
// on the moment google-services.json is dropped in at android/app/. It must be the
// file for this app's package name.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val releaseKeyProperties = Properties()
val releaseKeyPropertiesFile = rootProject.file("key.properties")
if (releaseKeyPropertiesFile.exists()) {
    FileInputStream(releaseKeyPropertiesFile).use { releaseKeyProperties.load(it) }
}
if (!releaseKeyPropertiesFile.exists() &&
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    throw GradleException("Release signing requires android/key.properties. See README.md.")
}

android {
    namespace = "in.bazaarx.marketplace_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time; older Android needs it
        // desugared.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Change this per client: it identifies the app on the phone and in the Play Store.
        applicationId = "in.bazaarx.store"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyPropertiesFile.exists()) {
            create("release") {
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
                storeFile = file(releaseKeyProperties.getProperty("storeFile"))
                storePassword = releaseKeyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseKeyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
