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
  "image": "ghcr.io/ppbds/devcontainers/dev:X.Y.Z"
}
```

Replace `X.Y.Z` with the latest tag from the [releases page](https://github.com/PPBDS/devcontainers/releases). Pin to a specific semver tag for stability — `:latest` floats with `main` and is fine for development but not for student-facing repos.

## Tag families

- `:latest` — most recent successful build from `main`. Convenient, not stable.
- `:X.Y.Z` and `:X.Y` — semver tags from a GitHub release on this repo. The canonical stable pin. `codespace-starter` pins to a specific `:X.Y.Z` and bumps it deliberately.

## Data-science tooling (student image)

The `student` image carries both languages students use:

- **R** — the rocker/tidyverse foundation, plus the PPBDS course packages (`tutorial.helpers`, `vscode.tutorials`, `misc.tutorials`, `primer.tutorials`), the `arf` console, Quarto, and `httpgd`.
- **Python** — a basic data-science stack installed with [`uv`](https://docs.astral.sh/uv/) into `/opt/venv` from a pinned lockfile (`student/requirements.lock`): numpy, pandas, matplotlib, seaborn, scikit-learn, statsmodels, jupyter, ipykernel. It's the default `python` on `PATH`, with a registered Jupyter kernel — so students can use Python in VS Code notebooks or in Quarto `.qmd` chunks (Quarto runs Python via the jupyter engine; no reticulate needed). The venv is group-writable, so students can `pip install` more packages.
- **Observable** — Quarto's `{ojs}` cells render interactive [Observable Plot](https://observablehq.com/plot/) / OJS in `.qmd` documents out of the box (no install); plus the [Observable Framework](https://observablehq.com/framework/) CLI (`observable`) for building standalone data-app projects.
- **Mapping / census** — `sf` + `tidycensus` (with `tigris`) for census-tract maps: pull ACS data and geometry in one call, render static maps with `ggplot2` or interactive ones with `leaflet` over free CARTO basemap tiles (no Mapbox token). Live census queries need a [free Census API key](https://api.census.gov/data/key_signup.html).
- **Interactive web viz + Shinylive** — for fancy interactive sites on static hosting: R htmlwidgets (`plotly`, `leaflet`, `DT`, `crosstalk`) and Python (`plotly`, `altair`, `folium`, `itables`) emit self-contained client-side JS; **Shinylive** (`shiny` + `shinylive`, R & Python) runs Shiny apps as WebAssembly, so they too deploy to GitHub Pages with no server.

Both are baked into the image, so they cost ~nothing at Codespace-creation time (the prebuild restores them).

## AI coding assistants

The `base` image (and therefore `dev` and `student`) ships four AI coding CLIs so that students and developers can pick the model that fits their cost and quality needs:

- **`claude`** — [Claude Code](https://docs.anthropic.com/claude-code). Anthropic's CLI, single-provider, uses Claude models. Highest quality, highest cost.
- **`codex`** — [Codex CLI](https://developers.openai.com/codex/cli). OpenAI's CLI, uses GPT/Codex models. Included with a ChatGPT Plus/Pro plan.
- **`agy`** — [Antigravity CLI](https://antigravity.google/docs/cli-overview). Google's terminal coding agent — the successor to the Gemini CLI, which Google [retired on 2026-06-18](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).
- **`aider`** — [Aider](https://aider.chat). Multi-provider. Point it at DeepSeek, OpenRouter, OpenAI, Anthropic, or any OpenAI-compatible endpoint. The cost-flexible option.

The images ship **no credentials**. The recommended way to authenticate is to **sign in on first run**: start the CLI and complete the account sign-in (a ChatGPT plan for `codex`, a Claude plan for `claude`, a Google account for `agy`). This bills against a flat-rate subscription rather than metered API calls. As a fallback — and the only option for `aider` — supply an API key via Codespaces user secrets (below); each CLI stays inert until it has either a sign-in or a key.

### Setting up API keys (the fallback path, per-user, one-time)

API keys are the **fallback** for students who prefer metered billing or who use `aider` (which is key-only). If you sign in to `claude`/`codex`/`agy` with an account instead, you need none of the keys below.

Configure each key as a personal Codespaces secret so it appears as an environment variable in every Codespace you launch — no need to re-enter it for each new Codespace.

1. Go to **https://github.com/settings/codespaces**.
2. Under **Codespaces secrets**, click **New secret**.
3. Add the secret name and value for each tool you plan to use:

   | Secret name | Used by | Where to get it |
   |---|---|---|
   | `ANTHROPIC_API_KEY` | `claude` (or sign in instead) | https://console.anthropic.com |
   | `ANTIGRAVITY_API_KEY` | `agy` (or sign in instead) | https://aistudio.google.com/apikey |
   | `OPENAI_API_KEY` | `aider` → OpenAI models | https://platform.openai.com/api-keys |
   | `DEEPSEEK_API_KEY` | `aider` → DeepSeek directly | https://platform.deepseek.com |
   | `OPENROUTER_API_KEY` | `aider` → any model via OpenRouter | https://openrouter.ai/keys |

   (`codex` authenticates by signing in with a ChatGPT plan, or via `codex login`; it does not read `OPENAI_API_KEY`.)

4. Under **Repository access**, grant access to the repos you launch Codespaces from (typically `PPBDS/codespace-starter` itself, and any other repo you open Codespaces on).
5. Save. The next Codespace you launch will have those env vars available, and the CLIs will pick them up automatically.

You only need to set up the keys for the tools you actually plan to use. Most students set one of (`DEEPSEEK_API_KEY` or `OPENROUTER_API_KEY`) plus optionally `ANTHROPIC_API_KEY` for higher-quality work when needed.

### Using cheaper models via Aider

For cost-sensitive work, point Aider at a cheap model:

```bash
# DeepSeek directly — typically ~$0.02–0.05 per 50K-token coding session
export DEEPSEEK_API_KEY=...   # already set via Codespaces secret
aider --model deepseek/deepseek-chat

# Or via OpenRouter — one key, hundreds of models you can swap between
export OPENROUTER_API_KEY=... # already set via Codespaces secret
aider --model openrouter/deepseek/deepseek-chat
aider --model openrouter/qwen/qwen-3-coder
aider --model openrouter/google/gemini-2.5-flash
```

For frontier-quality answers on hard problems, use `claude` directly (charged at Anthropic's rates) or `aider --model anthropic/claude-sonnet-4-6`.

## Architecture and design rationale

See [CLAUDE.md](CLAUDE.md). It documents what goes in each image, why, and the conventions to follow when changing them.
