import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.rakindotcom.ummah_assist"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rakindotcom.ummah_assist"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("production") {
            dimension = "distribution"
        }
        create("preview") {
            dimension = "distribution"
            applicationIdSuffix = ".preview"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            proguardFiles("proguard-rules.pro")
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Fail before packaging if a release key has not been provisioned.
val verifyReleaseSigning by tasks.registering {
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException("Release signing is missing. Run python3 tool/setup_android_signing.py or provision android/key.properties securely.")
        }
    }
}
tasks.matching {
    it.name.matches(Regex("^(assemble|bundle|package|sign)(Production|Preview)?Release(Bundle)?$"))
}.configureEach {
    dependsOn(verifyReleaseSigning)
}

// The local preview has no Firebase client. Its manifest also removes the
// native startup provider; skipping Dart initialization alone is insufficient.
tasks.configureEach {
    if (name.contains("Preview") &&
        (name.contains("GoogleServices") || name.contains("Crashlytics"))) {
        enabled = false
    }
}

// Validate the entire packaging graph before any task executes. A Dart-only
// entrypoint change must never package the preview under the production ID.
gradle.taskGraph.whenReady {
    val appTasks = allTasks.filter { it.project == project }
    fun usesEntrypoint(taskName: String, flavor: String): Boolean =
        taskName.matches(Regex("^(assemble|bundle|package|sign)${flavor}(Debug|Profile|Release)(Bundle)?$")) ||
            taskName.matches(Regex("^compileFlutterBuild${flavor}(Debug|Profile|Release)$"))
    val packagesPreview = appTasks.any {
        usesEntrypoint(it.name, "Preview")
    }
    val packagesProduction = appTasks.any {
        usesEntrypoint(it.name, "Production")
    }
    if (packagesPreview || packagesProduction) {
        val flutterRoot = rootProject.projectDir.parentFile
        val target = project.findProperty("target")?.toString()
            ?: flutter.target ?: "lib/main.dart"
        val targetFile = flutterRoot.resolve(target).canonicalFile
        val previewFile = flutterRoot.resolve("lib/main_productivity_preview.dart").canonicalFile
        if (packagesPreview && targetFile != previewFile) {
            throw GradleException("The preview flavor requires -t lib/main_productivity_preview.dart.")
        }
        if (packagesProduction && targetFile == previewFile) {
            throw GradleException("The preview entrypoint requires --flavor preview; it cannot use the production package.")
        }
    }
}
