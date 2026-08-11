allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // 구형 패키지의 namespace 자동 주입 및 Manifest package 속성 무시
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android != null) {
            if (android.namespace == null) {
                android.namespace = "com.example.${project.name.replace("-", "_")}"
            }
            // 최신 AGP 호환성을 위해 구형 매니페스트 package 속성 옵션 해제
            android.buildFeatures.buildConfig = true
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

// 💡 kakao_map_plugin 등의 구형 라이브러리 매니페스트 무시 처리
subprojects {
    tasks.withType(com.android.build.gradle.tasks.ExtractDeepLinksTask::class.java).configureEach {
        enabled = true
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}