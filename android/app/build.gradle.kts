plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

// Optional release keystore (CI writes android/keystore.properties from
// ANDROID_KEYSTORE_* secrets). Absent/incomplete -> debug keys (previous
// behavior) with a clear warning. No secrets are ever committed.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("keystore.properties")
var hasReleaseKeystore = false
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    val storePath = keystoreProperties.getProperty("storeFile")
    val storePassword = keystoreProperties.getProperty("storePassword")
    val keyAlias = keystoreProperties.getProperty("keyAlias")
    val keyPassword = keystoreProperties.getProperty("keyPassword")
    hasReleaseKeystore = !storePath.isNullOrBlank()
        && rootProject.file(storePath).exists()
        && !storePassword.isNullOrBlank()
        && !keyAlias.isNullOrBlank()
        && !keyPassword.isNullOrBlank()
    if (!hasReleaseKeystore) {
        println("WARNING: android/keystore.properties is incomplete or storeFile is missing - signing release with debug keys (unsigned for distribution).")
    }
} else {
    println("WARNING: android/keystore.properties not found - signing release with debug keys (unsigned for distribution). Provide ANDROID_KEYSTORE_* secrets in CI for a signed release.")
}

android {
    namespace = "com.example.accounting_system"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.accounting_system"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Release signing when CI provides the keystore, otherwise
            // keeps previous behavior (debug keys) so local builds work.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

// compilerOptions DSL replaces the deprecated kotlinOptions.jvmTarget.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
