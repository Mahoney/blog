---
layout: post
title: Intersection Types in Kotlin
date: '2020-05-14T12:30:00.003+01:00'
author: Robert Elliot
tags:
---

I recently found myself wanting intersection types in Kotlin. Specifically, I
was looking to write a client for WebDriver that depended on its `WebDriver` and
`HasInputDevices` interfaces but not on a concrete implementation like
`RemoteWebDriver`.

They are not natively supported yet (see [KT-13108: Denotable union and intersection types](https://youtrack.jetbrains.com/issue/KT-13108)).
However, you can get something very like them using Kotlin's `by` delegation:
```kotlin

// Third party code - I can't change
interface WebDriver
interface HasInputDevices
class RemoteWebDriver : WebDriver, HasInputDevices
class EventFiringWebDriver : WebDriver, HasInputDevices

// My code
interface CompositeWebDriver : WebDriver, HasInputDevices

class CompositeRemoteWebDriver(
  delegate: RemoteWebDriver = RemoteWebDriver()
) : CompositeWebDriver,
  WebDriver by delegate, 
  HasInputDevices by delegate

class CompositeEventFiringWebDriver(
  delegate: EventFiringWebDriver = EventFiringWebDriver()
) : CompositeWebDriver,
  WebDriver by delegate, 
  HasInputDevices by delegate

class WebDriverClient(driver: CompositeWebDriver) {
  // code depending on methods in WebDriver & HasInputDevices
}

// Client can now depend on either implementation
val client1 = WebDriverClient(CompositeRemoteWebDriver())
val client2 = WebDriverClient(CompositeEventFiringWebDriver())
```
It's still a bit painful; obviously there's a reasonable amount of repetition in
the declaration of each implementation, and adding a new interface to
`CompositeWebDriver`'s supertypes means also adding it as an extra supertype to
every implementation with a `by delegate` declaration. Still, it decouples the
client code from the actual third party implementation without having to
implement every method in each interface.
