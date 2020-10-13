---
layout: post
title: GitHub Actions Caching Strategy
date: '2020-10-13T22:48:351602625715+0100'
author: Robert Elliot
tags:
---

I've been trying to come up with a good caching strategy for a CI build, and
with the new `cache@v2` action I think I've worked it out.

I want:
* a nightly build without cache, to prove that the build works from scratch
  and isn't being propped up by a cache that cannot be recreated
* a regularly renewed cache, so that it doesn't keep growing - often the
  cache retrieval, expansion & update is the longest part of my build.

It occurred to me that these two requirements play nicely together - if the
nightly build could start with no cache, but prime the cache, then all builds
during the day would benefit from a nice minimal cache.

I think the following GitHub action achieves this, by including the current
date in the base cache key:

```yaml
name: My Build

on:
  schedule:
    # Daily at 2AM
    # * is a special character in YAML so you have to quote this string
    - cron: '0 2 * * *'

env:
  cache-name: my-build-1

jobs:
  build:
    runs-on: ubuntu-18.04

    steps:
      - uses: actions/checkout@v2

      - name: Get current date
        id: date
        run: echo "::set-output name=date::$(date +'%Y-%m-%d')"

      - name: Cache whatever
        uses: actions/cache@v2
        with:
          path: ~/path_needing_caching
          # Always want a cache miss on the first build of the day, which should
          # be the scheduled 2AM one. Proves the build works from scratch, and
          # primes a nice clean cache to work with each day.
          key: ${{ env.cache-name }}_${{ steps.date.outputs.date }}-${{ github.ref }}-${{ github.run_number }}
          restore-keys: |
               ${{ env.cache-name }}_${{ steps.date.outputs.date }}-${{ github.ref }}-
               ${{ env.cache-name }}_${{ steps.date.outputs.date }}-
``` 
