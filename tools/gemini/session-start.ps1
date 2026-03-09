param(
    [ValidateSet("backend", "anki", "web", "all")]
    [string]$Project = "all"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$targets = switch ($Project) {
    "backend" { @("flashcard-backend") }
    "anki"    { @("flashcard-anki") }
    "web"     { @("flashcard-web") }
    default   { @("flashcard-backend", "flashcard-anki", "flashcard-web") }
}

Write-Host "== Memogenesis Session Context (Gemini) =="
Write-Host "Root docs:"
Write-Host "- PRD.md"
Write-Host "- GEMINI.md"
Write-Host "- .gemini/styleguide.md"
Write-Host ""

foreach ($target in $targets) {
    $path = Join-Path $root $target
    Write-Host "== $target =="
    Write-Host "Read:"
    Write-Host "- $target/GEMINI.md"
    Write-Host "- $target/docs/architecture.md"
    if (Test-Path (Join-Path $path "docs/session-log.md")) {
        Write-Host "- Last sessions:"
        Get-Content (Join-Path $path "docs/session-log.md") -Tail 80  
    }
    if (Test-Path (Join-Path $path "docs/backlog.md")) {
        Write-Host "- Backlog:"
        Get-Content (Join-Path $path "docs/backlog.md")
    }
    Push-Location $path
    try {
        Write-Host "- Git status:"
        git status --short
    } finally {
        Pop-Location
    }
    Write-Host ""
}
