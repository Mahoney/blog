---
layout: post
title: Maps with typed keys in Kotlin
date: '2023-02-03T08:42:50.000+0000'
author: Robert Elliot
tags:
---

[Sam Cooper](https://medium.com/@sam-cooper) showed me on the Kotlin Slack that
you can create an immutable-ish class that is both a `Map<String, T>` and has
`val` properties representing compile time enforced keys on that `Map`, and
without much duplication.

Edit 2023-02-06 - we've made a couple of improvements:

* It's now invariant in `V`, the type of the values, so an
  `AbstractPropertyMap<String>` is a subtype of
  `AbstractPropertyMap<CharSequence>`
* The type of the properties is now captured by the type of the argument to
  `property`, so in an `AbstractPropertyMap<CharSequence>`
  `val aString by property("a string")` will have its type inferred as
  `String`. (This is obviously useful if extending  `AbstractPropertyMap<Any>`.)

Create this abstract class:

```kotlin
abstract class AbstractPropertyMap<out V>(
  private val properties: MutableMap<String, V> = mutableMapOf()
) : Map<String, V> by properties {
  protected fun <V2 : @UnsafeVariance V> property(initialValue: V2) =
    PropertyDelegateProvider<Any, ReadOnlyProperty<Any, V2>> { _, prop ->
      properties[prop.name] = initialValue
      ReadOnlyProperty(properties::getValue)
    }
}
```

You can then create subclasses as so:

```kotlin
class Links(
  id: String,
  otherId: String,
) : AbstractPropertyMap<URI>() {
  val self by property(URI.create("/v1/$id"))
  val other by property(URI.create("/v1/other/$otherId"))
}

val links = Links("1", "2")

links.self == URI.create("/v1/1")
links["self"] == links.self

links.other == URI.create("/v1/other/2")
links["other"] == links.other

links.keys == setOf("self", "other")
links.values.toList() == listOf(links.self, links.other)
links.entries == setOf(
  SimpleImmutableEntry("self", links.self),
  SimpleImmutableEntry("other", links.other)
)
```

Which begs the question - why?

I think the resulting class has a few nice properties:

1. `Links` *is* a `Map<String, URI>`, so you can retrieve values with keys only
   known at runtime and iterate over its entry set / key set / values without
   needing reflective access.
2. You only specify the key names once - no duplication, no room for error.
3. The compiler forces you to instantiate `Links` with all the expected keys.
4. The compiler enforces the type of all the properties created by delegation
5. You have type safe access to the properties on the resulting instance

In contrast, a `mapOf<String, URI>()` lacks 3 & 5. A simple class lacks 1 & 4.

A combination of the two could be made without the delegation magic, but would
be more noisy and require duplicating key names:

```kotlin
class Links(
    id: String,
    otherId: String,
) : AbstractMap<String, URI>() {
    val self = URI.create("/v1/$id")
    val other = URI.create("/v1/other/$otherId")

    override val entries: Set<Map.Entry<String, URI>> = setOf(
        AbstractMap.SimpleImmutableEntry("self", self),
        AbstractMap.SimpleImmutableEntry("other", other),
    )
}
```
