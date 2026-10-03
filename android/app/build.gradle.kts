plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.util.Base64

val keystorePropertiesFile = file(System.getenv("KAMUBUL_SIGNING")
    ?: "${System.getenv("APP_PUBLISHING_ROOT") ?: "D:/AppPublishing"}/apps/kamubul/credentials/android/key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) keystorePropertiesFile.inputStream().use { load(it) }
}
val admobAppId = keystoreProperties.getProperty(
    "admobAppId",
    "ca-app-pub-3940256099942544~3347511713",
)

android {
    namespace = "com.crazypenguin.kamubul"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        manifestPlaceholders["admobAppId"] = admobAppId
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.crazypenguin.kamubul"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = keystoreProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }?.let { keystorePropertiesFile.parentFile.resolve(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val checkReleaseSigning = tasks.register("checkReleaseSigning") {
    doLast {
        check(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
            !keystoreProperties.getProperty(it).isNullOrBlank()
        }) { "Production signing requires publishing key.properties: storeFile, storePassword, keyAlias, keyPassword. No debug-key fallback." }
        check(!keystoreProperties.getProperty("keyAlias").equals("androiddebugkey", ignoreCase = true)) {
            "Production signing cannot use the Android debug key."
        }
        check(keystorePropertiesFile.parentFile.resolve(keystoreProperties.getProperty("storeFile")).isFile) {
            "Production signing keystore file is missing."
        }
    }
}
val checkReleaseContact = tasks.register("checkReleaseContact") {
    doLast {
        val defines = try {
            (project.findProperty("dart-defines")?.toString() ?: "")
                .split(',').filter { it.isNotEmpty() }
                .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        } catch (_: IllegalArgumentException) {
            error("Release dart-defines must contain valid Base64 values.")
        }
        val email = defines.lastOrNull { it.startsWith("CONTACT_EMAIL=") }
            ?.substringAfter('=') ?: ""
        val domain = email.substringAfter('@', "").lowercase()
        check(Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(email) &&
            listOf("example.com", "example.net", "example.org", "test", "invalid", "localhost")
                .none { domain == it || domain.endsWith(".$it") }) {
            "Production requires a real CONTACT_EMAIL dart-define; missing or placeholder contact addresses are rejected."
        }
    }
}
// AGP omits validateSigningRelease when signing fields are incomplete; protect packaging itself.
tasks.matching { it.name in setOf("preReleaseBuild", "packageRelease", "packageReleaseBundle", "packageReleaseUniversalApk", "signReleaseBundle") }.configureEach {
    dependsOn(checkReleaseSigning, checkReleaseContact)
}

dependencies {
    // flutter_local_notifications Android 8+ API'leri için desugaring ister.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
