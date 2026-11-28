plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional local frontend prototype. No dependency or model is fetched by Gradle.
// Supply the audited source explicitly; ordinary Pocket builds remain supported.
val pinnedEspeakSource = rootProject.file("../validation/reader/private/espeak-4870adf-source/espeak-ng-4870adfa25b1a32b4361592f1be8a40337c58d6c")
val espeakSource = providers.gradleProperty("ureaderEspeakSource").orNull?.let { file(it) }
    ?: pinnedEspeakSource.takeIf { it.isDirectory }

android {
    namespace = "com.ureader.prototype"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ureader.prototype"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        // This feasibility prototype and its validated native bundle target ARM64.
        ndk { abiFilters += listOf("arm64-v8a") }
        if (espeakSource != null) {
            require(espeakSource.resolve("src/include/espeak-ng/speak_lib.h").isFile)
            externalNativeBuild {
                cmake { arguments += "-DESPEAK_SOURCE_DIR=${espeakSource.absolutePath.replace('\\', '/')}" }
            }
        }
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    if (espeakSource != null) {
        externalNativeBuild {
            cmake {
                path = file("src/main/cpp/CMakeLists.txt")
                version = "3.22.1"
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

// Optional audited offline mirror; a fresh clone resolves the same pinned artifact
// from Maven Central when the local mirror is absent.
val offlineOrt = rootProject.file("../validation/private/maven")
if (offlineOrt.isDirectory) {
    repositories {
        exclusiveContent {
            forRepository {
                maven {
                    name = "ureaderOfflineOrt"
                    url = uri(offlineOrt)
                }
            }
            filter { includeGroup("com.microsoft.onnxruntime") }
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    // Aligner le test sur le runner déjà résolu par integration_test/Flutter.
    // Le préflight utilise JUnit directement, sans l'extension AndroidJUnit4.
    androidTestImplementation("androidx.test:runner:1.3.0")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.25.0")
}
