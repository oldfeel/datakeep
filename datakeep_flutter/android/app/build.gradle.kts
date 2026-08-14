plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "site.datakeep"
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
        applicationId = "site.datakeep"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                cppFlags += ""
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.3")
    // gomobile：make -C syncthing_core android
    implementation(files("libs/syncthingcore.aar"))
}

tasks.register("checkSyncthingAar") {
    doLast {
        val aar = file("libs/syncthingcore.aar")
        if (!aar.exists()) {
            throw GradleException(
                "缺少 syncthingcore.aar。请先执行:\n" +
                    "  make -C datakeep_flutter/syncthing_core android\n" +
                    "（需 Go + Android NDK）"
            )
        }
    }
}

tasks.named("preBuild").configure { dependsOn("checkSyncthingAar") }
