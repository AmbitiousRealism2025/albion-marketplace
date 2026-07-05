# Albion permissions deny fragment
`permissions-deny.json` is the hard floor beneath `plugin/scripts/pre-tool-guard.sh`.
Albion sessions get it automatically: `bin/albion` injects the identical deny list via
`--settings` (`config/albion-settings.json`); a suite test keeps the two copies in sync.
Stock Claude Code users (plugin without the launcher) merge this fragment themselves.
It uses modern prefix deny syntax where Claude Code can express the command.
Keep local project allow rules separate so this deny list remains reviewable.
