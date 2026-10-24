import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push notifications. The Firebase plugin is applied only when a config file
// exists, so the apps build and run without a Firebase project and push switches
// on the moment google-services.json is dropped in. Each app has its own Firebase
// app (its own package name): src/shop/google-services.json and
// src/vendor/google-services.json. One at android/app/ is still honoured.
if (file("google-services.json").exists() ||
    file("src/shop/google-services.json").exists() ||
    file("src/vendor/google-services.json").exists()) {
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
        // The application id and name come from the flavor below: this repository
        // builds two apps. The code's own package (`namespace`) is shared.
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two apps from one codebase:
    //   shop   - the shopping app, lib/main.dart
    //   vendor - the seller app,   lib/main_vendor.dart
    // Build them with `flutter build apk --flavor shop` and
    // `flutter build apk --flavor vendor -t lib/main_vendor.dart`.
    flavorDimensions += "app"
    productFlavors {
        create("shop") {
            dimension = "app"
            applicationId = "in.bazaarx.marketplace_app"
            resValue("string", "app_name", "BazaarX")
        }
        create("vendor") {
            dimension = "app"
            applicationId = "in.bazaarx.seller"
            resValue("string", "app_name", "BazaarX Seller")
        }
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
