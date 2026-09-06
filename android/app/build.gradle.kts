plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.roadsos.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.roadsos.app"
        // flutter_webrtc 0.12.x requires minSdk 23 (Android 6.0).
        // Bumped from flutter.minSdkVersion (21) so the WebRTC in-app voice
        // call between Family Circle peers can compile + ship.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Enables multidex — required by the large number of methods from
        // supabase_flutter, powersync, firebase, flutter_gemma, etc.
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // R8 full-mode: dead-code elimination + name obfuscation.
            // Reduces APK size significantly (Dart AOT + native libs both shrink).
            isMinifyEnabled = true

            // Remove unused resources (drawables, layouts, strings, etc.).
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Signing with debug keys so `flutter build apk --release` works
            // in CI without a keystore secret.  Replace with a real signing
            // config before publishing to the Play Store.
            signingConfig = signingConfigs.getByName("debug")
        }

        debug {
            // Keep debug builds unminified so stack traces are readable.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Per-ABI split is opt-in via the Flutter CLI flag `--split-per-abi`
    // (see build_apk.yml). When that flag is set, Flutter 3.41 itself drives
    // `ndk.abiFilters` per output via `flutter.targetPlatforms`, so a static
    // `splits.abi { include(...) }` block here conflicts with the
    // auto-injected `ndk.abiFilters` and breaks every `flutter build apk` /
    // `assembleDebug` invocation:
    //
    //   Conflicting configuration : 'armeabi-v7a,arm64-v8a,x86_64' in ndk
    //   abiFilters cannot be present when splits abi filters are set.
    //
    // The CI workflow that wants per-ABI APKs already uses
    // `flutter build apk --split-per-abi`, which is enough. Leaving the
    // explicit `splits.abi` block here for "just in case" was actively
    // breaking debug builds and judge-demo APKs.
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.multidex:multidex:2.0.1")
}
