pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "AmneziaAndroid"

include(":core")
include(":mobile")
include(":tv")

// AmneziaWG 3.1 tunnel engine (org.amnezia.awg.*), built from the official
// amneziawg-android sources. Its native part needs the NDK; Go is downloaded
// by the library's own Makefile.
includeBuild("../Vendor/amneziawg-android") {
    dependencySubstitution {
        substitute(module("org.amnezia.awg:tunnel")).using(project(":tunnel"))
    }
}
