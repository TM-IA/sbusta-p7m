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
        versionCode = 2
        versionName = "0.2.0"
    }

    // Release signing: keystore path/passwords come from environment
    // variables (set by CI from GitHub Secrets), never committed.
    // Locally, with none of these set, the release build type just
    // falls back to unsigned — intentional, nobody needs to build a
    // signed release outside CI.
    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("SBUSTA_P7M_KEYSTORE_PATH")
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("SBUSTA_P7M_KEYSTORE_PASSWORD")
                keyAlias = "sbusta-p7m"
                keyPassword = System.getenv("SBUSTA_P7M_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (System.getenv("SBUSTA_P7M_KEYSTORE_PATH") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
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
