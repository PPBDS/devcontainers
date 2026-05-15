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

## AI coding assistants

The `base` image (and therefore `dev` and `student`) ships three AI coding CLIs so that students and developers can pick the model that fits their cost and quality needs:

- **`claude`** — [Claude Code](https://docs.anthropic.com/claude-code). Anthropic's CLI, single-provider, uses Claude models. Highest quality, highest cost.
- **`gemini`** — [Gemini CLI](https://github.com/google-gemini/gemini-cli). Google's CLI, free tier available.
- **`aider`** — [Aider](https://aider.chat). Multi-provider. Point it at DeepSeek, OpenRouter, OpenAI, Anthropic, or any OpenAI-compatible endpoint. The cost-flexible option.

The images themselves ship **no credentials**. Each CLI is inert until the relevant API key is present in the environment. Students supply their own keys via Codespaces user secrets (instructions below).

### Setting up API keys (per-user, one-time)

Configure each key as a personal Codespaces secret so it appears as an environment variable in every Codespace you launch — no need to re-enter it for each new Codespace.

1. Go to **https://github.com/settings/codespaces**.
2. Under **Codespaces secrets**, click **New secret**.
3. Add the secret name and value for each tool you plan to use:

   | Secret name | Used by | Where to get it |
   |---|---|---|
   | `ANTHROPIC_API_KEY` | `claude` | https://console.anthropic.com |
   | `GOOGLE_API_KEY` | `gemini` (paid tier; free tier uses OAuth) | https://aistudio.google.com/apikey |
   | `DEEPSEEK_API_KEY` | `aider` → DeepSeek directly | https://platform.deepseek.com |
   | `OPENROUTER_API_KEY` | `aider` → any model via OpenRouter | https://openrouter.ai/keys |

4. Under **Repository access**, grant access to the repos you launch Codespaces from (typically your `codespace-starter`-derived repo).
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
