plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tech.shupi.mydata"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tech.shupi.mydata"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // 关键配置：使用传统打包方式，确保 libsyncthing.so 正确安装
    // 否则基于 app bundles 的安装中，原生库不会出现在正确位置
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    
    // 明确指定 sourceSets，确保 jniLibs 被包含
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

flutter {
    source = "../.."
}

repositories {
    flatDir {
        dirs("libs")
    }
}

dependencies {
    // HTTP 客户端
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    
    // JSON 处理
    implementation("com.google.code.gson:gson:2.10.1")
    
    // Backend Go 绑定 (gomobile AAR)
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}
