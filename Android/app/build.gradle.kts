plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Versionen skrivs av Release Please i Android/version.txt. versionCode sätts i releasejobbet.
val appVersion = rootProject.file("version.txt").readText().trim()

android {
    namespace = "se.hardyson.sophamtning"
    // Compose kräver API 37.2 för att kompilera.
    compileSdk {
        version = release(37) { minorApiLevel = 2 }
    }

    defaultConfig {
        applicationId = "se.hardyson.sophamtning"
        minSdk = 31
        targetSdk = 37
        versionCode = (findProperty("versionCode") as String?)?.toInt() ?: 1
        versionName = appVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    jvmToolchain(21)
}

// Typsnitten delas med iOS och kopieras in när appen byggs, så att de bara finns i ett exemplar i repot.
abstract class CopyFonts : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val fonts: DirectoryProperty

    @get:OutputDirectory
    abstract val output: DirectoryProperty

    @TaskAction
    fun copy() {
        val dir = output.get().asFile.resolve("font")
        dir.deleteRecursively()
        dir.mkdirs()
        for (name in listOf("Fredoka", "Nunito")) {
            // Resursnamn får bara ha gemener.
            fonts.file("$name.ttf").get().asFile.copyTo(dir.resolve("${name.lowercase()}.ttf"), overwrite = true)
        }
    }
}

val copyFonts = tasks.register<CopyFonts>("copyFonts") {
    fonts.set(rootProject.layout.projectDirectory.dir("../iOS/Packages/SophamtningKit/Sources/SophamtningDesign/Resources/Fonts"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(copyFonts, CopyFonts::output)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
}
