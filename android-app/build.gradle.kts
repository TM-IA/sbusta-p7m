// Root build file: plugin versions declared here, applied per-module.
//
// No separate Kotlin plugin: AGP 9.0+ has built-in Kotlin support, and
// applying org.jetbrains.kotlin.android alongside it is now an error
// (verified against a real CI failure, not assumed — this project has
// no local Gradle to catch this before pushing).
plugins {
    id("com.android.application") version "9.3.0" apply false
}
