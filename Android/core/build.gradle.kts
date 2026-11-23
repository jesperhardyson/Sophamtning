// Ren Kotlin utan Android-API:er, som SophamtningKit på iOS. Testerna körs på JVM utan emulator.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(21)
}

// Ortlistan delas med iOS och kopieras inte. Kommunkollen på båda plattformarna läser samma fil.
sourceSets.main {
    resources.srcDir("../../iOS/Packages/SophamtningKit/Sources/SophamtningKit/Kommun/Resources")
}

// Fixturerna delas med iOS och kopieras inte. Ett test på iOS och samma test här läser samma fil.
sourceSets.test {
    resources.srcDir("../../iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/Fixtures")
}

tasks.test {
    exclude("**/ContractTest*")
}

// Anropar det riktiga API:t. Körs för hand, som ContractTests på iOS: ./gradlew :core:contractTest
val contractTest by tasks.registering(Test::class) {
    description = "Kör kontraktstesterna mot Sopor API i produktion."
    group = "verification"
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    filter.includeTestsMatching("*ContractTest*")
    outputs.upToDateWhen { false }
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    api(libs.ktor.client.core)
    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.ktor.client.mock)
    testImplementation(libs.ktor.client.okhttp)
}
