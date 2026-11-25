import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jlleitschuh.gradle.ktlint")
}

// Los hallazgos que ya había viven en config/ktlint/baseline.xml (ruta por defecto); sólo fallan los nuevos.
// Regenerarla: ./gradlew ktlintGenerateBaseline
ktlint {
    version.set("1.8.0")
}

// Supabase: URL y clave anon en local.properties (git lo ignora). Sin clave, la app arranca en modo demo.
// La clave service_role NUNCA va aquí.
val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
// -Psupabase.url=… tiene prioridad: sirve para probar contra el Supabase local sin tocar el archivo.
fun local(key: String) = (findProperty(key) as String? ?: localProps.getProperty(key) ?: "").replace("\\", "\\\\").replace("\"", "\\\"")

// Firma de la versión release: almacén y contraseñas en local.properties (nunca en git):
//   release.storeFile=/ruta/al/almacen.jks   release.storePassword=…
//   release.keyAlias=…                       release.keyPassword=…
// Sin ellas, la release se firma con la clave de depuración y no se instala encima de la buena.
val releaseStore = (findProperty("release.storeFile") as String? ?: localProps.getProperty("release.storeFile"))
    ?.let { file(it) }?.takeIf { it.exists() }
fun rawLocal(key: String) = findProperty(key) as String? ?: localProps.getProperty(key)

android {
    namespace = "com.savethemoney.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.savethemoney.android"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.8.0"
        buildConfigField("String", "SUPABASE_URL", "\"${local("supabase.url")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${local("supabase.anonKey")}\"")
        // Logos de comercios: clave PUBLICABLE de logo.dev (pk_…) en local.properties como logodev.token. Opcional.
        buildConfigField("String", "LOGO_DEV_TOKEN", "\"${local("logodev.token")}\"")
    }

    signingConfigs {
        if (releaseStore != null) {
            create("release") {
                storeFile = releaseStore
                storePassword = rawLocal("release.storePassword")
                keyAlias = rawLocal("release.keyAlias")
                keyPassword = rawLocal("release.keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // -Pentrega: APK reducido con R8 (el de 37 MB no se puede enviar al móvil).
            isMinifyEnabled = project.hasProperty("entrega")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            // Gancho de capturas (--ei pantalla N): solo en la depuración local, nunca en un APK que va a un móvil.
            buildConfigField("boolean", "CAPTURAS", (!project.hasProperty("entrega")).toString())
        }
        release {
            buildConfigField("boolean", "CAPTURAS", "false")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    // Los avisos que ya había viven en la línea base; sólo fallan los nuevos. Regenerarla: ./gradlew updateLintBaseline
    lint { baseline = file("lint-baseline.xml") }
}

// Una release nunca debe apuntar al Supabase local ni salir con la clave de depuración:
// con la clave local la app recibe "Invalid API key" y cierra la sesión.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.startsWith("assembleRelease") || it.name.startsWith("bundleRelease") }) {
        val url = rawLocal("supabase.url") ?: ""
        val local = listOf("127.0.0.1", "localhost", "10.0.2.2").any { url.contains(it) }
        check(!local) { "La release apunta al Supabase local ($url). Pon la URL y la clave anon de la nube en local.properties." }
        check(releaseStore != null) { "Falta la firma de release (release.storeFile y compañía en local.properties)." }
    }
}

dependencies {
    val bom = platform("androidx.compose:compose-bom:2025.09.01")
    implementation(bom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.core:core-ktx:1.17.0")
    // supabase-kt 3.2.x es la última compilada con Kotlin 2.2 (la 3.3+ pide Kotlin 2.3).
    implementation(platform("io.github.jan-tennert.supabase:bom:3.2.6"))
    implementation("io.github.jan-tennert.supabase:auth-kt")
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.ktor:ktor-client-okhttp:3.3.1")
    implementation("com.google.zxing:core:3.5.3")
    implementation("androidx.camera:camera-camera2:1.6.2")
    implementation("androidx.camera:camera-lifecycle:1.6.2")
    implementation("androidx.camera:camera-view:1.6.2")
    testImplementation("junit:junit:4.13.2")
}

// Los vectores compartidos con iOS viven fuera del módulo: sin esto, cambiar uno no vuelve a lanzar las pruebas.
tasks.withType<Test>().configureEach { inputs.dir(rootProject.file("../testdata/vectors")) }
