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

// Compile every plugin module against the same SDK as :app.
//
// Plugins pin whatever platform was current when they shipped — jni, jni_flutter
// and just_audio still ask for android-35 — which would force this machine to
// keep every historical SDK platform installed just to build. compileSdk only
// controls which APIs are visible at compile time, and newer platforms are
// supersets, so raising it is safe. minSdk and targetSdk, which actually affect
// runtime behaviour, are left exactly as each plugin declared them.
subprojects {
    if (name == "app") return@subprojects
    afterEvaluate {
        val appCompileSdk = rootProject.project(":app").extensions
            .findByType(com.android.build.api.dsl.CommonExtension::class.java)
            ?.compileSdk ?: return@afterEvaluate
        extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.let { android ->
            if ((android.compileSdk ?: 0) < appCompileSdk) android.compileSdk = appCompileSdk
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
