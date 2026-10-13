pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google { url = uri("https://dl-ssl.google.com/dl/android/maven2/") }
        mavenCentral()
        gradlePluginPortal()
    }
}

// Some networks can't reach dl.google.com reliably; dl-ssl.google.com is
// Google's alternate host for the same Maven repository. This also covers
// repositories declared by plugins (e.g. passive_liveness's buildscript).
fun RepositoryHandler.useGoogleMavenMirror() =
    all {
        if (this is MavenArtifactRepository && url.host == "dl.google.com") {
            url = uri(url.toString().replace("://dl.google.com", "://dl-ssl.google.com"))
        }
    }

gradle.beforeProject {
    buildscript.repositories.useGoogleMavenMirror()
    repositories.useGoogleMavenMirror()
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
