// Plugins deklareras här och används i modulerna. Versionerna står i gradle/libs.versions.toml.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
