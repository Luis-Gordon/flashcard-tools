param(
    [string]$Summary = "Session work completed."
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

Write-Host "== Gemini Session End Checklist =="
Write-Host "Summary: $Summary"
Write-Host ""

Write-Host "1) Run quality gates"
& (Join-Path $PSScriptRoot "check.ps1") -Project auto

Write-Host ""
Write-Host "2) Update documentation for modified projects"
Write-Host "- Append docs/session-log.md"
Write-Host "- Update GEMINI.md current status / next tasks"
Write-Host "- Update docs/architecture.md only for structural changes"

Write-Host ""
Write-Host "3) Review pending changes by sub-project"
foreach ($p in @("flashcard-backend", "flashcard-anki", "flashcard-web")) {
    $path = Join-Path $root $p
    Push-Location $path
    try {
        $dirty = git status --short
        if ($dirty) {
            Write-Host "== $p =="
            git status --short
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "4) Commit each sub-project repo separately after review"  
