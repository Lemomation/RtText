import java.util.Base64

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Stable release signing: CI provides the keystore as a base64 secret plus a
// password; when either is absent (local builds), fall back to debug signing.
val envKeystoreB64 = System.getenv("KEYSTORE_BASE64")
val envKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
val envKeyAlias = System.getenv("KEY_ALIAS") ?: "rttext"
val hasReleaseKeystore = !envKeystoreB64.isNullOrBlank() && !envKeystorePassword.isNullOrBlank()

android {
    namespace = "com.lemomation.rttext"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lemomation.rttext"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val keystoreFile = rootProject.file("app/keystore.p12")
                if (!keystoreFile.exists()) {
                    keystoreFile.writeBytes(Base64.getDecoder().decode(envKeystoreB64))
                }
                storeFile = keystoreFile
                storePassword = envKeystorePassword
                keyAlias = envKeyAlias
                keyPassword = envKeystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
