#!/usr/bin/env bash
set -euo pipefail

main() {
  local title=${1:?'Must provide a blog title'}
  local author=${2:-'Robert Elliot'}

  local date && date=$(date +'%Y-%m-%d')
  local time && time=$(date +'%Y-%m-%dT%H:%M:%S.000%z')
  local path="_drafts/$date-$(slugify "$title").md"

  cat > "$path" <<EOF
---
layout: post
title: $(yaml_string "$title")
date: $(yaml_string "$time")
author: $(yaml_string "$author")
tags:
---


EOF

  echo "$path"
}

# Emits a single-quoted YAML scalar, which needs no escaping beyond doubling
# any single quote it contains. Without this a title containing a ':' is
# invalid YAML, and Jekyll renders the post with no title and the wrong URL.
yaml_string() {
  local value=$1
  printf "'%s'" "${value//\'/\'\'}"
}

# The slug becomes the post's URL, so reduce anything that is not
# alphanumeric to a single dash rather than escaping it there.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '-' \
    | sed -e 's/^-*//' -e 's/-*$//'
}

main "$@"
