allprojects {
    repositories {
        google()
        mavenCentral()
        // OHOS 镜像缺少 Android engine，直接加 Google Flutter Maven
        maven {
            url = uri("https://storage.googleapis.com/download.flutter.io")
        }
    }
}

// AGP 8.9+ 要求所有 android library 显式声明 namespace，老插件(camera_android 等)未设置。
// 对所有未设置 namespace 的 android 模块，fallback 到 com.{project.name}
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library") ||
            project.plugins.hasPlugin("com.android.application")
        ) {
            @Suppress("UnstableApiUsage")
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
                if (it.namespace == null) {
                    it.namespace = "com.${project.name}"
                }
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
