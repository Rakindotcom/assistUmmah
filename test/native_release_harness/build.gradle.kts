import java.util.Properties

plugins {
    id("com.android.application") version "9.0.1"
}

val repositoryRoot = projectDir.resolve("../..").canonicalFile
val keyProperties = Properties().apply {
    repositoryRoot.resolve("android/key.properties").inputStream().use { load(it) }
}

android {
    namespace = "com.rakindotcom.ummah_assist.release_harness"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.rakindotcom.ummah_assist.release_harness"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
    signingConfigs {
        create("audit") {
            storeFile = repositoryRoot.resolve("android/" + keyProperties.getProperty("storeFile"))
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
        }
    }
    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("audit")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// This separate APK contains the runner. The production APK is never rebuilt,
// patched or given test-only Flutter plugins by this project.
dependencies {
    implementation("androidx.test:runner:1.7.0")
    implementation("androidx.test.uiautomator:uiautomator:2.3.0")
    implementation("junit:junit:4.13.2")
}
