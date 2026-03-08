param(
    [Parameter(Mandatory=$true)]
    [string]$PlanFile,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

# Resolve paths
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$PlanFile = Resolve-Path $PlanFile -ErrorAction Stop
$templatePath = Join-Path $root ".claude" "templates" "plan-review-prompt.md"

if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found: $templatePath"
    exit 1
}

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$template = Get-Content -Path $templatePath -Raw

$codexPrompt = $template.Replace('{{PLAN_FILE_PATH}}', $PlanFile).Replace('{{REVIEWER_ID}}', 'codex')
$geminiPrompt = $template.Replace('{{PLAN_FILE_PATH}}', $PlanFile).Replace('{{REVIEWER_ID}}', 'gemini')

$codexOutputFile = Join-Path $OutputDir "codex-verdict.json"
$geminiOutputFile = Join-Path $OutputDir "gemini-verdict.json"

$timeout = 300

function Write-ErrorVerdict {
    param([string]$Reviewer, [string]$Summary, [string]$OutputPath)
    @{verdict="ERROR"; reviewer=$Reviewer; summary=$Summary; findings=@()} |
        ConvertTo-Json -Depth 5 | Set-Content $OutputPath -Encoding utf8
}

Write-Host "Starting Codex review..."

# --- Codex invocation ---
$codexJob = Start-Job -ScriptBlock {
    param($prompt, $outputFile)
    $prompt | codex exec - --sandbox read-only --output-last-message $outputFile
    return $LASTEXITCODE
} -ArgumentList $codexPrompt, $codexOutputFile

$codexCompleted = Wait-Job $codexJob -Timeout $timeout
if (-not $codexCompleted) {
    Stop-Job $codexJob
    Write-ErrorVerdict -Reviewer "codex" -Summary "Timed out after ${timeout}s" -OutputPath $codexOutputFile
    Write-Host "Codex: TIMED OUT"
} else {
    try {
        $codexExit = Receive-Job $codexJob
        if ($codexExit -ne 0) {
            Write-ErrorVerdict -Reviewer "codex" -Summary "Invocation failed (exit $codexExit)" -OutputPath $codexOutputFile
            Write-Host "Codex: FAILED (exit $codexExit)"
        } else {
            Write-Host "Codex: DONE"
        }
    } catch {
        Write-ErrorVerdict -Reviewer "codex" -Summary "Job exception: $_" -OutputPath $codexOutputFile
        Write-Host "Codex: EXCEPTION - $_"
    }
}
Remove-Job $codexJob -Force

Write-Host "Starting Gemini review..."

# --- Gemini invocation ---
$geminiJob = Start-Job -ScriptBlock {
    param($prompt, $outputFile)
    $raw = $prompt | gemini --approval-mode plan --output-format json
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        try {
            $envelope = $raw | ConvertFrom-Json -ErrorAction Stop
            $content = $envelope.response
            if (-not $content) { throw "response field missing or empty" }
            $content | Set-Content $outputFile -Encoding utf8
        } catch {
            @{verdict="ERROR"; reviewer="gemini";
              summary="Output parse failed: $_"; findings=@()} |
                ConvertTo-Json -Depth 5 | Set-Content $outputFile -Encoding utf8
            return 1
        }
    }
    return $exitCode
} -ArgumentList $geminiPrompt, $geminiOutputFile

$geminiCompleted = Wait-Job $geminiJob -Timeout $timeout
if (-not $geminiCompleted) {
    Stop-Job $geminiJob
    Write-ErrorVerdict -Reviewer "gemini" -Summary "Timed out after ${timeout}s" -OutputPath $geminiOutputFile
    Write-Host "Gemini: TIMED OUT"
} else {
    try {
        $geminiExit = Receive-Job $geminiJob
        if ($geminiExit -ne 0) {
            if (-not (Test-Path $geminiOutputFile) -or (Get-Item $geminiOutputFile).Length -eq 0) {
                Write-ErrorVerdict -Reviewer "gemini" -Summary "Invocation failed (exit $geminiExit)" -OutputPath $geminiOutputFile
            }
            Write-Host "Gemini: FAILED (exit $geminiExit)"
        } else {
            Write-Host "Gemini: DONE"
        }
    } catch {
        if (-not (Test-Path $geminiOutputFile) -or (Get-Item $geminiOutputFile).Length -eq 0) {
            Write-ErrorVerdict -Reviewer "gemini" -Summary "Job exception: $_" -OutputPath $geminiOutputFile
        }
        Write-Host "Gemini: EXCEPTION - $_"
    }
}
Remove-Job $geminiJob -Force

Write-Host ""
Write-Host "Results written to:"
Write-Host "  $codexOutputFile"
Write-Host "  $geminiOutputFile"
