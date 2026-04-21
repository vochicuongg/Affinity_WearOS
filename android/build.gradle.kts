allprojects {
    repositories {
        google()
        mavenCentral()
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

// ── Patch legacy plugins missing an Android namespace (AGP 8+ requirement) ──
// The `wear` plugin (v1.1.0) predates AGP 8's namespace requirement.
// We inject the namespace as soon as the Android library plugin is applied,
// BEFORE variant creation occurs.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (androidExt.namespace.isNullOrEmpty()) {
            // Read the package attribute from AndroidManifest.xml as fallback
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val pkg = Regex("""package="([^"]+)"""")
                    .find(manifestFile.readText())?.groupValues?.get(1)
                if (!pkg.isNullOrEmpty()) {
                    androidExt.namespace = pkg
                }
            }
        }
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
