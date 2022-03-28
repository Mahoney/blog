---
layout: post
title: Gradle in a Multistage Docker Build
date: '2022-02-17T11:36:28.000+0000'
author: Robert Elliot
tags:
---

I've been fighting with getting a nice 

```dockerfile
# syntax=docker/dockerfile:1.3.0-labs
FROM --platform=$BUILDPLATFORM alpine:3.15.0 as builder

RUN apk add --no-cache openjdk17=17.0.2_p8-r0

# The single use daemon will be unavoidable in future so don't waste time trying to prevent it
ENV GRADLE_OPTS='-Dorg.gradle.daemon=false'

RUN mkdir /home/dev
WORKDIR /home/dev

# Download gradle in a separate step to benefit from layer caching
COPY gradle/wrapper gradle/wrapper
COPY gradlew gradlew
RUN ./gradlew --version

COPY . .

RUN --mount=type=secret,id=gradle-props,target=/root/.gradle/gradle.properties \
    --mount=type=cache,target=/root/.gradle/caches \
    ./gradlew --no-watch-fs build || mkdir -p build


FROM scratch as build-output

COPY --from=builder /home/dev/build .


# The builder step is guaranteed not to fail, so that the worker output can be
# tagged and its contents (build reports) extracted.
# You run this as:
# `docker build . --target build-output --output build/docker-output && docker build .`
# to retrieve the build reports whether or not the previous line exited successfully.
# Workaround for https://github.com/moby/buildkit/issues/1421
FROM builder as checker
RUN --mount=type=secret,id=gradle-props,target=/root/.gradle/gradle.properties \
    --mount=type=cache,target=/root/.gradle/caches \
    ./gradlew --no-watch-fs --stacktrace build
```
