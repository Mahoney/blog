#!/usr/bin/env bash

main() {
  local title=${1:?'Must provide a blog title'}
  local author=${2:-'Robert Elliot'}

  local title_kebab_case && title_kebab_case=$(
    echo "${title// /-}" | tr '[:upper:]' '[:lower:]'
  )
  local time && time=$(date +'%Y-%m-%dT%H:%M:%S%s%z')
  local date && date=$(date +'%Y-%m-%d')

  echo "---
layout: post
title: $title
date: '$time'
author: $author
tags:
---


" > _drafts/"$date-$title_kebab_case.md"
}

main "$@"
