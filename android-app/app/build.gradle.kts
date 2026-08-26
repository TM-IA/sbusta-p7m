// No separate Kotlin plugin: AGP 9.0+ has built-in Kotlin support.
plugins {
    id("com.android.application")
}

android {
    namespace = "com.tmia.sbustap7m"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.tmia.sbustap7m"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // No "kotlinOptions" block: it's gone along with the separate
    // Kotlin plugin (verified via a second real CI failure —
    // "Unresolved reference 'kotlinOptions'" — not found documented
    // anywhere, so not guessed at). compileOptions above is what's
    // left to control Kotlin's JVM target under AGP's built-in Kotlin.

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.19.0")
    implementation("androidx.appcompat:appcompat:1.8.0")

    // CMS/PKCS7 parsing — same task as asn1crypto on the Python side.
    implementation("org.bouncycastle:bcpkix-jdk18on:1.80")

    testImplementation("junit:junit:4.13.2")
}
