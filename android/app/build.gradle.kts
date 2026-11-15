import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Supabase: URL y clave anon en local.properties (git lo ignora). Sin clave, la app arranca en modo demo.
// La clave service_role NUNCA va aquí.
val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
// -Psupabase.url=… tiene prioridad: sirve para probar contra el Supabase local sin tocar el archivo.
fun local(key: String) = (findProperty(key) as String? ?: localProps.getProperty(key) ?: "").replace("\\", "\\\\").replace("\"", "\\\"")

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
    }

    buildTypes {
        debug {
            // -Pentrega: APK reducido con R8 (el de 37 MB no se puede enviar al móvil).
            isMinifyEnabled = project.hasProperty("entrega")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            // shortcut: firma con la clave de depuración para poder instalar el APK hoy; usar una clave propia antes de publicar.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
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
