plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val tiandituKey = providers.gradleProperty("TDT_KEY")
    .orElse(providers.environmentVariable("TDT_KEY"))
    .orElse("")
    .get()
val tiandituSecret = providers.gradleProperty("TDT_SK")
    .orElse(providers.environmentVariable("TDT_SK"))
    .orElse("")
    .get()
val tiandituRouteKey = providers.gradleProperty("TDT_ROUTE_KEY")
    .orElse(providers.environmentVariable("TDT_ROUTE_KEY"))
    .orElse(tiandituKey)
    .get()
val tiandituRouteSecret = providers.gradleProperty("TDT_ROUTE_SK")
    .orElse(providers.environmentVariable("TDT_ROUTE_SK"))
    .orElse(tiandituSecret)
    .get()
fun quotedBuildConfig(value: String): String =
    "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    namespace = "com.example.sipon"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures { buildConfig = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sipon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "TDT_KEY", quotedBuildConfig(tiandituKey))
        buildConfigField("String", "TDT_SK", quotedBuildConfig(tiandituSecret))
        buildConfigField("String", "TDT_ROUTE_KEY", quotedBuildConfig(tiandituRouteKey))
        buildConfigField("String", "TDT_ROUTE_SK", quotedBuildConfig(tiandituRouteSecret))
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1")
    implementation("org.maplibre.gl:android-sdk:13.6.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}

flutter {
    source = "../.."
}
