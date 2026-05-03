# PPBDS devcontainers

Container infrastructure for the PPBDS GitHub organization. This repo publishes three Docker images to the GitHub Container Registry (GHCR); other PPBDS repos consume them via short `devcontainer.json` files.

## Images

| Image | Audience | Built from |
|---|---|---|
| `ghcr.io/ppbds/devcontainers/base`    | shared substrate (don't consume directly) | `rocker-org/devcontainer/tidyverse` |
| `ghcr.io/ppbds/devcontainers/dev`     | developing PPBDS R packages               | `base` |
| `ghcr.io/ppbds/devcontainers/student` | taking the data science course            | `base` |

## Consuming

In a downstream repo's `.devcontainer/devcontainer.json`:

```jsonc
{
  "image": "ghcr.io/ppbds/devcontainers/dev:0.1.0"
}
```

Pin to a semver tag (e.g. `:0.1.0`) for stability. `:latest` floats with `main` and is fine for development but not for student-facing repos.

## Tag families

- `:latest` — most recent successful build from `main`. Convenient, not stable.
- `:X.Y.Z` and `:X.Y` — semver tags from a GitHub release on this repo. The canonical stable pin.
- `:<semester>` (e.g. `:fa25`) — `student` only. A moving channel for a single semester, applied manually by retagging a tested release.

## Architecture and design rationale

See [CLAUDE.md](CLAUDE.md). It documents what goes in each image, why, and the conventions to follow when changing them.
