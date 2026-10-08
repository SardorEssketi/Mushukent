import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

val pushEnabled = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.any { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) == "ENABLE_ANDROID_PUSH=true"
        }.getOrDefault(false)
    } == true
val googleServicesConfig = file("google-services.json")
if (pushEnabled) {
    require(googleServicesConfig.isFile) {
        "ENABLE_ANDROID_PUSH=true requires frontend/android/app/google-services.json."
    }
}
if (googleServicesConfig.isFile) {
    apply(plugin = "com.google.gms.google-services")
}

val releaseKeystoreProperties = Properties()
val releaseKeystorePropertiesFile = rootProject.file("key.properties")
if (releaseKeystorePropertiesFile.exists()) {
    releaseKeystorePropertiesFile.inputStream().use { releaseKeystoreProperties.load(it) }
}

val requestedReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val requiredReleaseSigningProperties = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
if (requestedReleaseBuild) {
    require(releaseKeystorePropertiesFile.isFile) {
        "Release signing requires frontend/android/key.properties."
    }
    requiredReleaseSigningProperties.forEach { propertyName ->
        require(!releaseKeystoreProperties.getProperty(propertyName).isNullOrBlank()) {
            "Release signing property '$propertyName' is missing from key.properties."
        }
    }
    val releaseStoreFile = project.file(releaseKeystoreProperties.getProperty("storeFile"))
    require(releaseStoreFile.isFile) {
        "Release signing keystore does not exist at the configured storeFile path."
    }
}

android {
    namespace = "uz.mushukistan.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "uz.mushukistan.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = releaseKeystoreProperties["storeFile"] as String?
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = releaseKeystoreProperties["storePassword"] as String?
            keyAlias = releaseKeystoreProperties["keyAlias"] as String?
            keyPassword = releaseKeystoreProperties["keyPassword"] as String?
        }
    }

    buildTypes {
        release {
            if (releaseKeystorePropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("release")
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
