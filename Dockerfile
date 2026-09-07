# Pins the toolchain the site is built with, so a build does not depend on
# whatever Ruby happens to be installed on the host. GitHub Pages builds the
# published site itself; this only has to agree with it closely enough to
# preview changes.
FROM ruby:3.3-slim

# Native extensions in the github-pages dependency tree (eventmachine, ffi)
# need a compiler.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

# Gems and their lockfile live in the image, not the mounted repo: an
# unprivileged container user can then read them without write access, and
# bundler resolves from the baked lockfile instead of hitting the network on
# every build.
ENV BUNDLE_GEMFILE=/opt/gems/Gemfile
COPY Gemfile /opt/gems/
RUN bundle install

WORKDIR /site
