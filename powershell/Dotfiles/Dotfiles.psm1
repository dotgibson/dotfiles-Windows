# ============================================================================
#  Dotfiles.psm1  -  the dotfiles-Windows module (B7, hybrid migration).
#
#  Owns the profile's NON-INTERACTIVE surface so its helpers stop leaking into
#  the global session as a flat pile of global: functions. STAGE 1 re-homes the
#  pure helper library (core/05-lib.ps1); later stages migrate the command verbs.
#
#  The interactive layer stays dot-sourced at GLOBAL scope by profile.ps1 and is
#  deliberately NOT moved here: a module-scoped `prompt` function is ignored by
#  the host (so starship's prompt would silently revert), and the tool inits /
#  PSReadLine keybinds / argument completers / CommandNotFoundAction all expect
#  to register against the global session.
#
#  The pure-helper FILE stays at core/05-lib.ps1 — the test suite, install.ps1,
#  uninstall.ps1 and Install-Packages.ps1 dot-source it directly, which still
#  works because dot-sourcing defines the functions in the CALLER's scope. This
#  module simply dot-sources the same file and re-exports the curated surface
#  declared in Dotfiles.psd1 (FunctionsToExport), the single source of truth.
# ============================================================================

. (Join-Path $PSScriptRoot '../core/05-lib.ps1')
