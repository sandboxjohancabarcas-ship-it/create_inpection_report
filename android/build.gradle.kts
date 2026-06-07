rootProject.layout.buildDirectory.set(layout.projectDirectory.dir("../build"))

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    project.layout.buildDirectory.set(rootProject.layout.buildDirectory.dir(project.name))

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
