---
layout: post
title: Working with Clikt
date: '2023-06-20T10:06:04.000+0100'
author: Robert Elliot
tags:
  - clikt
  - kotlin
---

Couple of quick notes on working with [Clikt](https://ajalt.github.io/clikt/),
the Kotlin CLI library: 

## Using Clikt as a pure parser

If all you want is to turn command line arguments into a data class, without
using the Clikt Command abstraction, you can do it as follows:

```kotlin
import com.github.ajalt.clikt.core.NoOpCliktCommand
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required

fun main(vararg args: String) {
  val config: Config = CliParser.parseConfig(*args)
}

data class Config(val username: String)

class CliParser private constructor() : NoOpCliktCommand(
  name = "",
  help = "help text",
) {

  private val username: String by option(help = "the username").required()

  private fun toConfig() = Config(username = username)

  companion object {

    fun parseConfig(vararg args: String): Config =
      CliParser()
        .apply { parse(args.toList()) }
        .toConfig()
  }
}
```

## Injecting the environment as a map

If you want to decouple Clikt from `System.getenv` you can do so as so:

```kotlin
class CliParser(
  env: Map<String, String> = System.getenv()
) : CliktCommand {

  init {
    context {
      envarReader = env::get
      autoEnvvarPrefix = "MY_APP"
    }
  }
}
```
