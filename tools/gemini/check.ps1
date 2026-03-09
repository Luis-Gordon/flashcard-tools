param(
    [ValidateSet("backend", "anki", "web", "all", "auto")]
    [string]$Project = "auto"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$projects = @{
    backend = @{
        Path = "flashcard-backend"
        Steps = @("npm run typecheck", "npm run lint", "npm run test")
    }
    anki = @{
        Path = "flashcard-anki"
        Steps = @("flake8 src/", "mypy src/", "pytest tests/ -v")     
    }
    web = @{
        Path = "flashcard-web"
        Steps = @("npm run typecheck", "npm run lint", "npm run test")
    }
}

function Get-Targets {
    param([string]$Requested)
    if ($Requested -eq "all") { return @("backend", "anki", "web") }  
    if ($Requested -ne "auto") { return @($Requested) }

    $detected = @()
    foreach ($name in @("backend", "anki", "web")) {
        $path = Join-Path $root $projects[$name].Path
        Push-Location $path
        try {
            $dirty = git status --short
            if ($dirty) { $detected += $name }
        } finally {
            Pop-Location
        }
    }
    return $detected
}

function Run-Command {
    param([string]$Command)
    & pwsh -NoProfile -Command $Command
    return $LASTEXITCODE
}

$targets = Get-Targets -Requested $Project
if (-not $targets -or $targets.Count -eq 0) {
    Write-Host "No changes detected. Pass -Project backend|anki|web|all."
    exit 0
}

$results = @()

foreach ($target in $targets) {
    $cfg = $projects[$target]
    $path = Join-Path $root $cfg.Path
    $typecheck = "SKIP"
    $lint = "SKIP"
    $test = "SKIP"
    $status = "PASS"

    Write-Host "Checking project: $target..."
    Push-Location $path
    try {
        $typecheck = "PASS"
        if ((Run-Command -Command $cfg.Steps[0]) -ne 0) {
            $typecheck = "FAIL"; $status = "FAIL"
        }
        if ($status -eq "PASS") {
            $lint = "PASS"
            if ((Run-Command -Command $cfg.Steps[1]) -ne 0) {
                $lint = "FAIL"; $status = "FAIL"
            }
        }
        if ($status -eq "PASS") {
            $test = "PASS"
            if ((Run-Command -Command $cfg.Steps[2]) -ne 0) {
                $test = "FAIL"; $status = "FAIL"
            }
        }
    } finally {
        Pop-Location
    }

    $results += [pscustomobject]@{
        Project   = $target
        Typecheck = $typecheck
        Lint      = $lint
        Test      = $test
        Status    = $status
    }
}

$results | Format-Table -AutoSize
