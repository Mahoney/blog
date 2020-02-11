---
layout: post
title: Tips for Using Gradle to build JPMS Modules when Developing with IntelliJ
date: '2019-11-23T14:05:00.003+01:00'
author: Robert Elliot
tags:
modified_time: '2019-11-23T14:05:00.003+01:00'
---

I've recently been trying to get a project going with the following stack:

* Language: [Kotlin](https://kotlinlang.org/)
* Target: [JVM Module (JPMS)](https://openjdk.java.net/projects/jigsaw/spec/)
* UI Framework: [OpenJavaFX](https://openjfx.io/)
* Build system: [Gradle](https://gradle.org/) using the [Kotlin DSL](https://docs.gradle.org/current/userguide/kotlin_dsl.html)
* IDE: [IntelliJ IDEA](https://www.jetbrains.com/idea/)

In principle this didn't seem an unreasonable stack. JavaFX is meant to be the
latest and greatest JVM UI Framework. It requires JPMS usage, but then JPMS is
meant to be the new "correct" way to develop for the JVM. Gradle is the oldest
and most mature JVM build system that isn't awful (no I don't want to program in
XML). It has good IntelliJ support. Kotlin is developed by IntelliJ and uses
gradle as its build system; I've been programming with it for a year or two now
and found it mature, well designed and a pleasure to use.

In practice I found it surprisingly painful to get things to a) work and b) work
the way I wanted them to. So if you're doing something similar you can now learn
from my pain.

Tips:

## Add plugins as runtime dependencies in `buildSrc/`

### `buildSrc/build.gradle.kts`
```kotlin
plugins {
  `kotlin-dsl`
}

repositories {
  gradlePluginPortal()
}

dependencies {
  testRuntimeOnly("org.javamodularity:moduleplugin:1.5.0")
  testRuntimeOnly("org.openjfx:javafx-plugin:0.0.8")
}
```

This was the most useful thing for me in debugging plugin behaviour. Having a
`buildSrc/build.gradle.kts` with the `kotlin-dsl` plugin makes IntelliJ add the
gradle jars & sources to `External Libraries`. Adding any plugins you use as
runtime dependencies in `buildSrc/` means they also get added to
`External Libraries`. This allows you to browse their source, hyperlink around
it and set breakpoints. I find it invaluable in debugging plugin behaviour.

(This tip may become irrelevant if a future version of IntelliJ automatically
adds these sources to  `External Libraries` - vote on
[IDEA-197182](https://youtrack.jetbrains.com/issue/IDEA-197182) to help make
that happen.)

## Plugin application order matters

I am using the [org.javamodularity:moduleplugin](https://github.com/java9-modularity/gradle-modules-plugin)
to manage the JPMS behaviour because gradle has no out of the box support. It
needs to read the java main sourceSet to find & read `module-info.java`. If you
change the sourceSet directories it will pick up on that change - but you need
to apply moduleplugin *after* you change the srcSets, not before. Otherwise it
picks up the standard src dirs and cannot find the file.

Irritatingly when it doesn't find `module-info.java` it just silently does not
apply itself, leaving you to try and understand the downstream errors, rather
than failing good and hard and explaining the problem to you.

## Use moduleplugin version 1.5.0 not 1.6.0

I encountered two issues with version 1.6.0:
* It has a breaking change (on a minor version increment...) and
  [javafx-plugin:0.0.8](https://github.com/openjfx/javafx-gradle-plugin) depends
  on a class that is no longer present in 1.6.0
* It gets the module path wrong when trying to run a standard mixed (java &
  kotlin) module

## Things you just need to know about the gradle kotlin dsl

Configuring sub project plugins in a root project that should not apply the
plugins is hard and confusing. Trial and error have shown me the following:

Import configurations:
```kotlin
val api by configurations
val implementation by configurations
val testImplementation by configurations

dependencies {
  api(kotlin("stdlib"))
  implementation("...")
  testImplementation("...")
}
```
Import tasks:
```kotlin
val test by tasks.existing(Test::class)
tasks {
  test {
    useJUnitPlatform()
  }
}
```
Configure java:
```kotlin
configure<JavaPluginExtension> {
  sourceCompatibility = javaVersion
  targetCompatibility = javaVersion

  configure<SourceSetContainer> {
    named("main") { java.setSrcDirs(setOf("src")) }
    named("test") { java.setSrcDirs(setOf("tests")) }
  }
}
```
Configure kotlin:
```kotlin
configure<KotlinJvmProjectExtension> {
  sourceSets {
    named("main") { kotlin.setSrcDirs(setOf("src")) }
    named("test") { kotlin.setSrcDirs(setOf("tests")) }
  }
}
```

## Consider applying config by applied plugin

If you've got a multi-project build it may be convenient to configure sub
projects by whether or not they have some plugin applied to them. In my root
project I do this:
```kotlin
subprojects {
  pluginManager.withPlugin("kotlin") {
    // All config common to kotlin projects
  }
}
```

Then in any sub project I just need this in `build.gradle.kts` to apply all my
common kotlin config:
```kotlin
plugins {
  kotlin("jvm")
}
```

This has the additional benefit that, because you explicitly applied the plugin,
you have access to the plugin's dsl in that sub project's `build.gradle.kts`.

## Share functions between multiple `build.gradle.kts` by putting them in `buildSrc/`

Any code in `buildSrc/<main src dir>` is available to all `build.gradle.kts` in
the project and sub projects.

For instance if I create a file in `buildSrc/<main src dir>` called
`DependencyVersions.kt` like so:
```kotlin
fun kotlintest(module: String) = "io.kotlintest:kotlintest-$module:3.4.2"
fun arrowkt(module: String) = "io.arrow-kt:arrow-$arrowModule:0.10.2"
fun kotlinCoroutines(module: String) = "org.jetbrains.kotlinx:kotlinx-coroutines-$module:1.3.2"
```

then in any `build.gradle.kts` I can use those functions to depend on modules as
so:
```kotlin
dependencies {
  implementation(kotlintest("core"))
  implementation(arrowkt("core"))
  implementation(kotlinCoroutines("core"))
  implementation(kotlinCoroutines("javafx"))
}
```


## Prevent intermediate directories becoming projects

By default, if you include deeply nested projects like this:

#### `settings.gradle.kts`
```kotlin
include(
  ":app",
  ":core",
  ":ui:api",
  ":ui:javafx"
)
```
the intermediate directories (in this case `ui`) will become gradle projects,
despite lacking a `build.gradle.kts` and any other files. This can cause very
confusing errors like this one:
```
FAILURE: Build failed with an exception.

* What went wrong:
A problem occurred configuring project ':app'.
> A problem occurred configuring project ':ui:api'.
   > Could not open cache directory add8lpbh91wftlbit7lhn37cw (/home/runner/.gradle/caches/6.0.1/gradle-kotlin-dsl/add8lpbh91wftlbit7lhn37cw).
      > org.gradle.api.internal.initialization.DefaultClassLoaderScope@47f3a892 must be locked before it can be used to compute a classpath!
```

You can fix this by including the specific project and setting its dir
explicitly, as so:

#### `settings.gradle.kts`
```kotlin
include(
  ":app",
  ":core",
  ":ui-api",
  ":ui-javafx"
)
project(":ui-api").projectDir = file("ui/api")
project(":ui-javafx").projectDir = file("ui/javafx")
```

## Example Project

These ideas can be seen implemented at
[https://github.com/Mahoney-example/example-gradle-kotlin-javafx](https://github.com/Mahoney-example/example-gradle-kotlin-javafx)
