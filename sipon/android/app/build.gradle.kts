import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val petalLocalProperties = Properties().apply {
    val propertiesFile = rootProject.file("local.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it) }
}
val petalMapKey = providers.gradleProperty("PETAL_MAP_KEY")
    .orElse(providers.environmentVariable("PETAL_MAP_KEY"))
    .orElse(petalLocalProperties.getProperty("PETAL_MAP_KEY", "")).get()
val petalRouteKey = providers.gradleProperty("PETAL_ROUTE_KEY")
    .orElse(providers.environmentVariable("PETAL_ROUTE_KEY"))
    .orElse(petalLocalProperties.getProperty("PETAL_ROUTE_KEY", petalMapKey)).get()
val petalAppId = providers.gradleProperty("PETAL_APP_ID")
    .orElse(providers.environmentVariable("PETAL_APP_ID"))
    .orElse(petalLocalProperties.getProperty("PETAL_APP_ID", "")).get()
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
        buildConfigField("String", "PETAL_MAP_KEY", quotedBuildConfig(petalMapKey))
        buildConfigField("String", "PETAL_ROUTE_KEY", quotedBuildConfig(petalRouteKey))
        buildConfigField("String", "PETAL_APP_ID", quotedBuildConfig(petalAppId))
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
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    // U2NETP 随 assets 打包，CPU 本地推理，不依赖 GMS 或运行时下载。
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.22.0")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    implementation("com.huawei.hms:maps:6.15.1.322")
    implementation("com.huawei.hms:maps-basic:6.15.1.322")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}

flutter {
    source = "../.."
}
