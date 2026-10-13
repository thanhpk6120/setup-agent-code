# ==============================================================================
# TRASH-CLI.PS1 — CLI WRAPPER CHO HÀM TRASH
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\trash-guard.ps1"
trash @args
