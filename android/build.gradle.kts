allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ---------------------------------------------------------------------------
// Pin plugin subprojects to an installable compileSdk.
//
// flutter_secure_storage 11 declares `compileSdk = 37`. AGP resolves that to
// the platform hash "android-37", but Google has moved to minor-versioned
// platforms: the SDK now ships `android-37.0` (AndroidVersion.ApiLevel=37.0)
// and no plain `android-37` package exists. The build then fails with
// "Failed to find target with hash string 'android-37'".
//
// 36 is the highest platform that still resolves, and it matches the app's own
// compileSdk. Remove this block once AGP understands the minor-versioned
// platform naming.
// ---------------------------------------------------------------------------
val pinnedCompileSdk = 36

subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") ?: return@afterEvaluate
        val current = runCatching {
            android.javaClass.getMethod("getCompileSdkVersion").invoke(android) as? String
        }.getOrNull()

        if (current != null && current != "android-$pinnedCompileSdk") {
            val setter = android.javaClass.methods.firstOrNull {
                it.name == "compileSdkVersion" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }
            if (setter != null) {
                logger.lifecycle(
                    "Pinning ${project.name} compileSdk $current -> android-$pinnedCompileSdk"
                )
                setter.invoke(android, pinnedCompileSdk)
            }
        }
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
