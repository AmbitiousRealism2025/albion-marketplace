# Albion plugin marketplace

The Claude Code plugin marketplace for
[Albion](https://github.com/AmbitiousRealism2025/Albion) — run Claude Code on
GLM-5.2 with an always-on operating charter and deterministic enforcement
hooks, side by side with your stock Claude Code.

## Install

Inside Claude Code:

```
/plugin marketplace add AmbitiousRealism2025/albion-marketplace
/plugin install albion@albion
```

Enabling the plugin puts the `albion` launcher on your PATH. Set up your Z.ai
credential (`albion-setup`, or `export ALBION_ZAI_TOKEN=...`), check your
setup with `albion-doctor --live`, then run `albion`.

The plugin's hooks are **inert in stock `claude` sessions** — they activate
only in sessions started by the `albion` launcher, so installing it never
changes your normal Claude Code behavior.

Docs, source, issues, and the development record:
[github.com/AmbitiousRealism2025/Albion](https://github.com/AmbitiousRealism2025/Albion).
The packaged plugin here corresponds to Albion release
[v0.3.0](https://github.com/AmbitiousRealism2025/Albion/releases/tag/v0.3.0).
