plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.flutterberlin.litertlm_host"
    compileSdk = flutter.compileSdkVersion
    // Pinned to match the flutter_gemma example (packages/flutter_gemma/example/android/app/build.gradle.kts):
    // the LiteRT-LM native prebuilts are built against this NDK.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.flutterberlin.litertlm_host"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 24 to match the flutter_gemma example — Android API < 30 can
        // hit a libLiteRtLm.so pthread_cond_clockwait issue (#265), so this is
        // a floor, not a workaround for that (this test device is API 32).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Required for `integration_test` to run under `gradlew assembleAndroidTest`
        // on Firebase Test Lab. Local `flutter test -d <device>` injects this on
        // the fly, but the raw gradlew path FTL uses does not — without it the
        // androidTest APK ships zero test classes and FTL reports a vacuous
        // "OK (0 tests)". Mirrors packages/flutter_gemma/example.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
