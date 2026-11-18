import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

check(keystorePropertiesFile.isFile) {
    "Missing android/key.properties. Please create it before building."
}

keystorePropertiesFile.inputStream().use {
    keystoreProperties.load(it)
}

fun requiredSigningProperty(name: String): String =
    keystoreProperties.getProperty(name)
        ?.takeIf(String::isNotBlank)
        ?: error("Missing '$name' in android/key.properties.")

android {
    namespace = "com.example.buid_arch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("buildArchDebug") {
            storeFile = rootProject.file(requiredSigningProperty("storeFile"))
            storePassword = requiredSigningProperty("storePassword")
            keyAlias = requiredSigningProperty("keyAlias")
            keyPassword = requiredSigningProperty("keyPassword")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.buid_arch"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("buildArchDebug")
        }

        getByName("release") {
            // Configure a separate production signing key before publishing.
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
