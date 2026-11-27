import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Clé du SDK Google Maps natif : jamais écrite en dur dans le dépôt.
// Ordre de recherche : variable d'environnement MAPS_API_KEY,
// android/local.properties (MAPS_API_KEY=...), puis GOOGLE_MAPS_MOBILE_API_KEY
// dans le fichier .env de l'API Moovi (../api/.env à côté de l'application).
fun resolveMapsApiKey(): String {
    System.getenv("MAPS_API_KEY")?.takeIf { it.isNotBlank() }?.let { return it }
    val localProps = rootProject.file("local.properties")
    if (localProps.exists()) {
        val props = Properties()
        FileInputStream(localProps).use { props.load(it) }
        props.getProperty("MAPS_API_KEY")?.takeIf { it.isNotBlank() }?.let { return it }
    }
    val apiEnv = rootProject.file("../../api/.env")
    if (apiEnv.exists()) {
        apiEnv.readLines()
            .map { it.trim() }
            .firstOrNull { it.startsWith("GOOGLE_MAPS_MOBILE_API_KEY=") }
            ?.substringAfter("=")
            ?.trim()
            ?.trim('"', '\'')
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }
    }
    logger.warn("MOOVI : aucune clé Google Maps trouvée (MAPS_API_KEY) - la carte restera vide.")
    return ""
}

android {
    namespace = "wicotech.com.moovi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    //ce que j'ai ajouté

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requis par flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "wicotech.com.moovi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = resolveMapsApiKey()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            val storeFilePath = keystoreProperties["storeFile"] as String?
            storeFile = if (storeFilePath != null) file(storeFilePath) else null
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
