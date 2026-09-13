plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.media:media:1.7.0")
}

android {
    namespace = "com.bobby.omni_player"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.bobby.sarvamplay"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
