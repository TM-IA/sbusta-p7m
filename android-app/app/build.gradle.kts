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

    kotlinOptions {
        jvmTarget = "17"
    }

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
