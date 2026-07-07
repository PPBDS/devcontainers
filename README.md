# PPBDS devcontainer

Container infrastructure for the PPBDS GitHub organization. This repo publishes **one Docker image** to the GitHub Container Registry:

    ghcr.io/ppbds/devcontainer

It serves everyone: students taking the data science course (via [codespace-starter](https://github.com/PPBDS/codespace-starter)) and developers working on PPBDS packages.

> **Note:** this image replaced the old `devcontainers/base`, `devcontainers/dev`, and `devcontainers/student` trio in v1.0.0. The old packages remain on GHCR at their final tags so existing pins keep working, but they receive no new versions — switch to `ghcr.io/ppbds/devcontainer`.

## Consuming

In a downstream repo's `.devcontainer/devcontainer.json`:

```jsonc
{
  "image": "ghcr.io/ppbds/devcontainer:X.Y.Z"
}
```

Replace `X.Y.Z` with the latest tag from the [releases page](https://github.com/PPBDS/devcontainers/releases). Pin to a specific semver tag — `:latest` floats with `main` and is not for student-facing (or, since 2026-07, package-repo) config.

## Tag families

- `:latest` — most recent successful build from `main`. Convenient, not stable.
- `:X.Y.Z` and `:X.Y` — semver tags from a GitHub release on this repo. The canonical stable pin.

## What's inside

- **R** — the rocker/tidyverse foundation, the PPBDS course packages (`tutorial.helpers`, `vscode.tutorials`, `misc.tutorials`, `primer.tutorials`), the `arf` console, Quarto, `httpgd`, and `pak`.
- **Modeling** — `tidymodels` plus engines (`xgboost`, `lightgbm`, `catboost`, `randomForest`, `ranger`, `glmnet`, `bonsai`) and `brms` for Bayesian regression via Stan.
- **Inference reporting & presentation** — `gt`, `marginaleffects`, `patchwork`, `easystats` (used throughout the primer book and tutorials).
- **Mapping / census** — `sf` + `tidycensus` (with `tigris`) for census-tract maps, plus the [Kyle Walker](https://walker-data.com) toolkit: `mapgl` (token-free WebGL vector maps via MapLibre + CARTO styles), `crsuggest`, and `idbr`. Live census queries need a [free Census API key](https://api.census.gov/data/key_signup.html).
- **Interactive web viz + Shinylive** — R htmlwidgets (`plotly`, `leaflet`, `DT`, `crosstalk`) and Python (`plotly`, `altair`, `folium`, `itables`) emit self-contained client-side JS; **Shinylive** (R & Python) runs Shiny apps as WebAssembly — everything publishes to static hosting (GitHub Pages).
- **Python** — a data-science stack installed with [`uv`](https://docs.astral.sh/uv/) into `/opt/venv` from a pinned lockfile: numpy, pandas, matplotlib, seaborn, scikit-learn, statsmodels, jupyter, ipykernel. Default `python` on `PATH`, registered Jupyter kernel, group-writable so `pip install` works.
- **Observable** — Quarto's `{ojs}` cells render Observable Plot / OJS out of the box; the [Observable Framework](https://observablehq.com/framework/) CLI is installed for standalone data-app projects.
- **Package development** — `devtools`, `pkgdown`, `roxygen2`, `testthat`, `usethis`, and the R CMD check toolchain (incl. `qpdf`).
- **AI coding assistants** — see below.

## AI coding assistants

The image ships four AI coding CLIs so users can pick the model that fits their cost and quality needs:

- **`claude`** — [Claude Code](https://docs.anthropic.com/claude-code). Anthropic's CLI, single-provider, uses Claude models. Highest quality, highest cost.
- **`codex`** — [Codex CLI](https://developers.openai.com/codex/cli). OpenAI's CLI, uses GPT/Codex models. Included with a ChatGPT Plus/Pro plan.
- **`agy`** — [Antigravity CLI](https://antigravity.google/docs/cli-overview). Google's terminal coding agent — the successor to the Gemini CLI, which Google [retired on 2026-06-18](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).
- **`aider`** — [Aider](https://aider.chat). Multi-provider. Point it at DeepSeek, OpenRouter, OpenAI, Anthropic, or any OpenAI-compatible endpoint. The cost-flexible option.

The image ships **no credentials**. The recommended way to authenticate is to **sign in on first run**: start the CLI and complete the account sign-in (a ChatGPT plan for `codex`, a Claude plan for `claude`, a Google account for `agy`). This bills against a flat-rate subscription rather than metered API calls. As a fallback — and the only option for `aider` — supply an API key via Codespaces user secrets (below); each CLI stays inert until it has either a sign-in or a key.

### Setting up API keys (the fallback path, per-user, one-time)

Configure each key as a personal Codespaces secret so it appears as an environment variable in every Codespace you launch.

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

4. Under **Repository access**, grant access to the repos you launch Codespaces from.
5. Save. The next Codespace you launch will have those env vars available.

### Using cheaper models via Aider

```bash
# DeepSeek directly — typically ~$0.02–0.05 per 50K-token coding session
aider --model deepseek/deepseek-chat

# Or via OpenRouter — one key, hundreds of models you can swap between
aider --model openrouter/deepseek/deepseek-chat
aider --model openrouter/qwen/qwen-3-coder
aider --model openrouter/google/gemini-2.5-flash
```

For frontier-quality answers on hard problems, use `claude` directly (charged at Anthropic's rates) or `aider --model anthropic/claude-sonnet-4-6`.

## Architecture and design rationale

See [CLAUDE.md](CLAUDE.md) and the comments in the [Dockerfile](Dockerfile) — the Dockerfile comments are the canonical record of what's installed and why.
