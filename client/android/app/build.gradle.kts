import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val crosslinkChannel = providers.environmentVariable("CROSSLINK_BUILD_CHANNEL").orElse("production").get()
require(crosslinkChannel in listOf("qa","production")) { "Invalid build channel" }
val releasePropertiesFile = file(providers.environmentVariable("CROSSLINK_SIGNING_PROPERTIES").orElse(rootProject.file("../../.tools/signing/key.properties").absolutePath).get())
val releaseProperties = Properties().apply { if(releasePropertiesFile.isFile) releasePropertiesFile.inputStream().use { load(it) } }
val hasReleaseSigning = releasePropertiesFile.isFile && listOf("storeFile","storePassword","keyAlias","keyPassword").all { !releaseProperties.getProperty(it).isNullOrBlank() }
gradle.taskGraph.whenReady {
 if(allTasks.any { it.project == project && it.name.contains("Release") }) {
  check(hasReleaseSigning) { "CrossLink release signing configuration is required; debug signing is forbidden" }
 }
}

android {
    namespace = "com.crosslink.crosslink"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures { resValues = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if(crosslinkChannel == "qa") "com.crosslink.crosslink.qa" else "com.crosslink.crosslink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName + if(crosslinkChannel == "qa") "-qa" else ""
        resValue("string","app_name",if(crosslinkChannel == "qa") "CrossLink QA" else "CrossLink")
    }

    signingConfigs {
        create("crosslinkRelease") {
            if(hasReleaseSigning) {
                storeFile=file(releaseProperties.getProperty("storeFile"))
                storePassword=releaseProperties.getProperty("storePassword")
                keyAlias=releaseProperties.getProperty("keyAlias")
                keyPassword=releaseProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("crosslinkRelease")
            isDebuggable = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
  implementation("androidx.core:core-ktx:1.17.0")
  implementation("com.squareup.okhttp3:okhttp:4.12.0")
  testImplementation("junit:junit:4.13.2")
  testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
  testImplementation("org.json:json:20240303")
}
