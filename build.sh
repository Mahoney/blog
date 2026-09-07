#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE=blog-builder

main() {
  local serve=false

  while getopts "s" opt; do
    case "$opt" in
      s) serve=true ;;
      *) usage ;;
    esac
  done

  cd "$(dirname "${BASH_SOURCE[0]}")"

  docker build --quiet --tag "$IMAGE" . > /dev/null

  if "$serve"; then
    run --publish 4000:4000 -- jekyll serve --host 0.0.0.0 --livereload
  else
    run -- jekyll build
  fi
}

# Runs bundler in the image against the repo mounted at /site. Args before `--`
# are for docker, args after it for bundler.
run() {
  local docker_args=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    docker_args+=("$1")
    shift
  done
  shift

  # Only allocate a terminal when there is one to allocate, so the script still
  # works from a hook or CI.
  if [[ -t 0 ]]; then
    docker_args+=(--interactive --tty)
  fi

  docker run \
    --rm \
    --volume "$PWD:/site" \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    "${docker_args[@]}" \
    "$IMAGE" \
    bundle exec "$@"
}

usage() {
  echo "Usage: $(basename "${BASH_SOURCE[0]}") [-s]" >&2
  echo "  -s  serve the site on http://localhost:4000 instead of building" >&2
  exit 1
}

main "$@"
