# Software Development Thoughts

Source for the blog at [blog.lidalia.org.uk](https://blog.lidalia.org.uk).

A [Jekyll](https://jekyllrb.com/) site published by GitHub Pages, which builds
and deploys it on every push to `master`. There is no CI workflow: GitHub does
the build itself, so anything that only works locally will not reach the
published site.

## Prerequisites

Docker, and nothing else. The build runs entirely inside a container because
the gems now require Ruby 3.2 or later, which is newer than the Ruby macOS
ships.

## Working on the site

| Command          | What it does                                              |
|------------------|-----------------------------------------------------------|
| `./build.sh`     | Builds the site into `_site/`                             |
| `./build.sh -s`  | Serves it at http://localhost:4000, reloading on a change |
| `./new_post.sh "Some Title"` | Creates a dated skeleton in `_drafts/`        |

Preview with `./build.sh -s` rather than opening `_site/index.html` directly.
Stylesheets are referenced from the site root (`/assets/css/style.css`), so
over `file://` they resolve against the filesystem root and nothing is styled.

A post in `_drafts/` is not published until it moves to `_posts/` with a date
in its filename. To see drafts while writing, pass `--drafts` to Jekyll
directly, using the image `build.sh` has already built:

```sh
docker run --rm -v "$PWD:/site" -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -p 4000:4000 blog-builder bundle exec jekyll serve --host 0.0.0.0 --drafts
```

Note that a title containing a `:` must be quoted, or the front matter is not
valid YAML and Jekyll silently renders the post with no title and the wrong
URL.

## Theme

The theme is [Minima 3](https://github.com/jekyll/minima), consumed via
`remote_theme` because it has never been released as a gem. It is pinned to an
explicit commit in `_config.yml`: `remote_theme` otherwise tracks Minima's
`master`, and the site would change appearance on its own.

The `auto` skin follows the reader's operating system light/dark preference.

Two files deliberately override the theme, and both need re-checking whenever
that pin is bumped:

- `_layouts/post.html` is a copy of Minima's, changed only to route post
  content through `_includes/anchor_headings.html`. Minima offers no hook
  around post content, so shadowing the layout is the only way in. The file
  records the commit it was copied from.
- `_sass/minima/custom-styles.scss` is Minima's documented styling hook, and
  styles the heading anchors.

## Heading anchors

`h2`–`h6` in a post get a `#` link, revealed on hover, so readers can link to
a section. This uses
[jekyll-anchor-headings](https://github.com/allejo/jekyll-anchor-headings),
vendored into `_includes/` rather than added to the `Gemfile`: GitHub Pages
refuses to run third-party plugins, and being pure Liquid it needs no
JavaScript, so the anchors are in the served HTML.

Kramdown generates the heading `id`s these point at, so an anchor's URL is
derived from the heading text and will change if you reword a heading.

## Gotchas

`exclude` in `_config.yml` *replaces* Jekyll's default exclusions instead of
adding to them. Anything removed from that list gets treated as site content —
a stale `vendor/` directory, for instance, will fail the build on Liquid
syntax inside the gems.
