import org.gradle.api.tasks.Exec

plugins {
    id("ru.vyarus.use-python") version "3.0.0"
}

tasks.register<Exec>("buildNative") {
    workingDir = file("$projectDir/../lib_build")
    commandLine("go", "run", "main.go")
    inputs.dir("$projectDir/../lib_build")
    outputs.dir("$projectDir/../app/src/main/jniLibs/")
}

/**
 * Use separate task instead of standard clean(), so these folders aren't deleted by `gradle clean`.
 */
tasks.register<Delete>("cleanNative") {
    delete("$projectDir/../app/src/main/jniLibs/")
    delete("gobuild")
}
