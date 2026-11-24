import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val debugSigningProperties = Properties()
val debugSigningPropertiesFile = rootProject.file("key.properties")
if (debugSigningPropertiesFile.isFile) {
    debugSigningPropertiesFile.inputStream().use {
        debugSigningProperties.load(it)
    }
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("release-key.properties")
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use {
        releaseSigningProperties.load(it)
    }
}

fun requiredSigningProperty(
    properties: Properties,
    name: String,
    propertiesFile: String,
): String =
    properties.getProperty(name)
        ?.takeIf(String::isNotBlank)
        ?: error("Missing '$name' in android/$propertiesFile.")

val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (isReleaseBuild && !releaseSigningPropertiesFile.isFile) {
    error(
        "Missing android/release-key.properties. Configure a production "
            + "signing key before building a release artifact.",
    )
}

android {
    namespace = "com.buildarchsolutions.buildarch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (debugSigningPropertiesFile.isFile) {
            create("buildArchDebug") {
                storeFile = rootProject.file(
                    requiredSigningProperty(
                        debugSigningProperties,
                        "storeFile",
                        "key.properties",
                    ),
                )
                storePassword = requiredSigningProperty(
                    debugSigningProperties,
                    "storePassword",
                    "key.properties",
                )
                keyAlias = requiredSigningProperty(
                    debugSigningProperties,
                    "keyAlias",
                    "key.properties",
                )
                keyPassword = requiredSigningProperty(
                    debugSigningProperties,
                    "keyPassword",
                    "key.properties",
                )
            }
        }
        if (releaseSigningPropertiesFile.isFile) {
            create("productionRelease") {
                val releaseStoreFile = rootProject.file(
                    requiredSigningProperty(
                        releaseSigningProperties,
                        "storeFile",
                        "release-key.properties",
                    ),
                )
                check(releaseStoreFile.isFile) {
                    "Production Android keystore file was not found."
                }
                storeFile = releaseStoreFile
                storePassword = requiredSigningProperty(
                    releaseSigningProperties,
                    "storePassword",
                    "release-key.properties",
                )
                keyAlias = requiredSigningProperty(
                    releaseSigningProperties,
                    "keyAlias",
                    "release-key.properties",
                )
                keyPassword = requiredSigningProperty(
                    releaseSigningProperties,
                    "keyPassword",
                    "release-key.properties",
                )
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.buildarchsolutions.buildarch"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            if (debugSigningPropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("buildArchDebug")
            }
        }

        getByName("release") {
            if (releaseSigningPropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("productionRelease")
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
