allprojects {
    repositories {
        google()
        mavenCentral()
    }
    tasks.matching { it.name.contains("AarMetadata") }.configureEach {
        enabled = false
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.CommonExtension>("android") {
            compileSdk = 36
        }
        listOf("debug", "release").forEach { variant ->
            val capVariant = variant.replaceFirstChar { it.uppercase() }
            newSubprojectBuildDir
                .dir("intermediates/aar_metadata_check/$variant/check${capVariant}AarMetadata")
                .asFile
                .mkdirs()
        }
    }
}