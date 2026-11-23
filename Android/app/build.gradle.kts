plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Versionen skrivs av Release Please i Android/version.txt. versionCode sätts i releasejobbet, och ett testbygge får
// sin version med -PversionName, så att ingen fil i repot ändras.
val appVersion = rootProject.file("version.txt").readText().trim()

// Uppladdningsnyckeln för Google Play läses från miljövariabler och finns aldrig i repot. SOPHAMTNING_UPLOAD_KEYSTORE är
// sökvägen till nyckelfilen. I releasejobbet skrivs filen från en secret och tas bort efteråt. Se docs/android-google-play.md.
val uploadKeyVariables = listOf(
    "SOPHAMTNING_UPLOAD_KEYSTORE",
    "SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD",
    "SOPHAMTNING_UPLOAD_KEY_ALIAS",
    "SOPHAMTNING_UPLOAD_KEY_PASSWORD",
)
val uploadKey = uploadKeyVariables.associateWith { providers.environmentVariable(it).orNull?.takeIf(String::isNotBlank) }
val hasUploadKey = uploadKey.values.all { it != null }

// Med -Psigning=debug signeras release-bygget med debug-nyckeln, bara för att prova R8-bygget i emulatorn. Ett sådant
// bygge går inte att ladda upp till Play.
val signWithDebugKey = providers.gradleProperty("signing").orNull == "debug"

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
        versionName = (findProperty("versionName") as String?) ?: appVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            if (hasUploadKey) {
                storeFile = file(uploadKey.getValue("SOPHAMTNING_UPLOAD_KEYSTORE")!!)
                storePassword = uploadKey.getValue("SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD")
                keyAlias = uploadKey.getValue("SOPHAMTNING_UPLOAD_KEY_ALIAS")
                keyPassword = uploadKey.getValue("SOPHAMTNING_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Utan nyckel blir signeringen tom, och checkReleaseSigning stoppar bygget innan något paketeras.
            signingConfig = when {
                signWithDebugKey -> signingConfigs.getByName("debug")
                hasUploadKey -> signingConfigs.getByName("release")
                else -> null
            }
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    // Svaren som UI-testerna på iOS använder delas och kopieras inte. Testerna här läser samma filer.
    sourceSets["test"].resources.srcDir("../../iOS/Sophamtning/UITestData")
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

// Nyheterna i appen läses från Android/CHANGELOG.md, som Release Please skriver. Filen finns först efter den första
// releasen, och tills dess följer ingen fil med och sidan Nyheter visar en tom text.
abstract class CopyChangelog : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val changelog: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val output: DirectoryProperty

    @TaskAction
    fun copy() {
        val dir = output.get().asFile
        dir.deleteRecursively()
        dir.mkdirs()
        changelog.files.filter { it.isFile }.forEach { it.copyTo(dir.resolve("CHANGELOG.md"), overwrite = true) }
    }
}

val copyChangelog = tasks.register<CopyChangelog>("copyChangelog") {
    changelog.from(rootProject.file("CHANGELOG.md"))
}

// Stoppar release-bygget med ett tydligt fel när uppladdningsnyckeln saknas, så att ett osignerat bygge aldrig når Play.
// Lösenorden är inte indata till uppgiften, bara vilka variabler som saknas och sökvägen till nyckelfilen.
abstract class CheckReleaseSigning : DefaultTask() {
    @get:Input
    abstract val debugSigning: Property<Boolean>

    @get:Input
    abstract val missing: ListProperty<String>

    @get:Input
    @get:Optional
    abstract val keystore: Property<String>

    @TaskAction
    fun check() {
        if (debugSigning.get()) {
            logger.warn("Release-bygget signeras med debug-nyckeln (-Psigning=debug). Det går bara att prova i en emulator.")
            return
        }
        val missing = missing.get()
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Release-bygget behöver uppladdningsnyckeln, och de här miljövariablerna saknas: " +
                    missing.joinToString() + ". Se docs/android-google-play.md. För att bara prova bygget i en emulator, " +
                    "signera med debug-nyckeln: -Psigning=debug",
            )
        }
        val file = File(keystore.get())
        if (!file.isFile) throw GradleException("Nyckelfilen i SOPHAMTNING_UPLOAD_KEYSTORE finns inte: ${file.path}")
    }
}

val checkReleaseSigning = tasks.register<CheckReleaseSigning>("checkReleaseSigning") {
    debugSigning.set(signWithDebugKey)
    missing.set(uploadKey.filterValues { it == null }.keys.toList())
    keystore.set(uploadKey.getValue("SOPHAMTNING_UPLOAD_KEYSTORE")?.let { file(it).path })
    // Körs alltid, eftersom miljön kan ha ändrats sedan förra bygget.
    outputs.upToDateWhen { false }
}

// Både AAB:n och APK:n kontrolleras innan de paketeras.
tasks.matching { it.name == "packageReleaseBundle" || it.name == "packageRelease" }.configureEach {
    dependsOn(checkReleaseSigning)
}

androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(copyFonts, CopyFonts::output)
        variant.sources.assets?.addGeneratedSourceDirectory(copyChangelog, CopyChangelog::output)
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
    implementation(libs.androidx.compose.material.icons.core)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.browser)
    implementation(libs.androidx.work.runtime)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.material3)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.androidx.work.testing)
    testImplementation(libs.androidx.glance.appwidget.testing)
}
