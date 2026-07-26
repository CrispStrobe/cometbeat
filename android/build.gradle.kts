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

// Raise the compileSdk of any PLUGIN subproject that pins one older than we
// need. Without this the Android build dies at :onnxruntime:checkDebugAarMetadata:
//
//   Dependency 'androidx.fragment:fragment:1.7.1' requires libraries and
//   applications that depend on it to compile against version 34 or later of
//   the Android APIs. :onnxruntime is currently compiled against android-33.
//
// onnxruntime is a pub package that hardcodes `compileSdkVersion 33`, so it
// cannot be edited here, and compileSdk only affects which APIs a library is
// COMPILED against — minSdk/targetSdk, which decide what devices run the app
// and how it behaves, are untouched. That is why this is safe to force.
//
// Duck-typed on purpose: this build declares AGP 9, where the extension type
// that owns `compileSdk` has moved between major versions. Reflection keeps the
// root project from hard-depending on one AGP's DSL classes, and a miss is
// logged rather than failing the build.
val requiredCompileSdk = 36

subprojects {
    if (project.name == "app") return@subprojects
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val current = runCatching {
            androidExt.javaClass.getMethod("getCompileSdk").invoke(androidExt) as? Int
        }.getOrNull()
        if (current == null || current >= requiredCompileSdk) return@afterEvaluate
        val raised = runCatching {
            androidExt.javaClass
                .getMethod("setCompileSdk", Integer::class.java)
                .invoke(androidExt, requiredCompileSdk)
        }.isSuccess
        if (raised) {
            logger.lifecycle(
                "compileSdk: raised ${project.name} from $current to $requiredCompileSdk",
            )
        } else {
            logger.warn(
                "compileSdk: could NOT raise ${project.name} from $current — " +
                    "AGP's DSL likely changed; see android/build.gradle.kts",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
