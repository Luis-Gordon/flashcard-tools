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

# If the plan file is outside the project root, copy it into the project so
# sandboxed reviewers (Gemini) can read it.
$planFileForReview = $PlanFile
if (-not $PlanFile.ToString().StartsWith($root)) {
    $tempPlanDir = Join-Path $root "docs" "plans" ".review-input"
    if (-not (Test-Path $tempPlanDir)) {
        New-Item -ItemType Directory -Path $tempPlanDir -Force | Out-Null
    }
    $tempPlanFile = Join-Path $tempPlanDir (Split-Path -Leaf $PlanFile)
    Copy-Item -Path $PlanFile -Destination $tempPlanFile -Force
    $planFileForReview = Resolve-Path $tempPlanFile
}

$codexPrompt = $template.Replace('{{PLAN_FILE_PATH}}', $planFileForReview).Replace('{{REVIEWER_ID}}', 'codex')
$geminiPrompt = $template.Replace('{{PLAN_FILE_PATH}}', $planFileForReview).Replace('{{REVIEWER_ID}}', 'gemini')

$codexOutputFile = Join-Path $OutputDir "codex-verdict.json"
$geminiOutputFile = Join-Path $OutputDir "gemini-verdict.json"

$timeout = 600  # seconds

function Write-ErrorVerdict {
    param([string]$Reviewer, [string]$Summary, [string]$OutputPath)
    @{verdict="ERROR"; reviewer=$Reviewer; summary=$Summary; findings=@()} |
        ConvertTo-Json -Depth 5 | Set-Content $OutputPath -Encoding utf8
}

# Create temp files for stdin redirection and stdout/stderr capture
$codexPromptFile = [System.IO.Path]::GetTempFileName()
$geminiPromptFile = [System.IO.Path]::GetTempFileName()
$codexStdout = [System.IO.Path]::GetTempFileName()
$codexStderr = [System.IO.Path]::GetTempFileName()
$geminiStdout = [System.IO.Path]::GetTempFileName()
$geminiStderr = [System.IO.Path]::GetTempFileName()

try {
    # Write prompts to temp files for stdin redirection
    Set-Content -Path $codexPromptFile -Value $codexPrompt -Encoding utf8
    Set-Content -Path $geminiPromptFile -Value $geminiPrompt -Encoding utf8

    # --- Launch both reviewers in parallel ---
    Write-Host "Starting Codex and Gemini reviews in parallel..."

    # Codex: use cmd /c with type pipe to avoid Start-Process stdin issues on Windows
    $codexProc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c","type","`"$codexPromptFile`"","|","codex.cmd","exec","-","-m","gpt-5.3-codex","--sandbox","read-only","--output-last-message","`"$codexOutputFile`"",">","`"$codexStdout`"","2>","`"$codexStderr`"" `
        -NoNewWindow -PassThru

    # Gemini: use cmd /c with type pipe to avoid Start-Process stdin issues
    # -y (yolo) auto-approves tool calls so Gemini can read files without blocking
    $geminiProc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c","type","`"$geminiPromptFile`"","|","gemini.cmd","--output-format","json","-m","gemini-2.5-pro","-y","-p","""""",">","`"$geminiStdout`"","2>","`"$geminiStderr`"" `
        -NoNewWindow -PassThru

    # --- Wait for both with timeout ---
    $codexDone = $codexProc.WaitForExit($timeout * 1000)
    if (-not $codexDone) {
        try { $codexProc.Kill() } catch {}
        Write-ErrorVerdict -Reviewer "codex" -Summary "Timed out after ${timeout}s" -OutputPath $codexOutputFile
        Write-Host "Codex: TIMED OUT"
    } elseif ($codexProc.ExitCode -ne 0) {
        $stderrContent = if (Test-Path $codexStderr) { Get-Content $codexStderr -Raw } else { "" }
        Write-ErrorVerdict -Reviewer "codex" -Summary "Invocation failed (exit $($codexProc.ExitCode)): $stderrContent" -OutputPath $codexOutputFile
        Write-Host "Codex: FAILED (exit $($codexProc.ExitCode))"
    } else {
        Write-Host "Codex: DONE"
    }

    $geminiDone = $geminiProc.WaitForExit($timeout * 1000)
    if (-not $geminiDone) {
        try { $geminiProc.Kill() } catch {}
        Write-ErrorVerdict -Reviewer "gemini" -Summary "Timed out after ${timeout}s" -OutputPath $geminiOutputFile
        Write-Host "Gemini: TIMED OUT"
    } elseif ($geminiProc.ExitCode -ne 0) {
        $stderrContent = if (Test-Path $geminiStderr) { Get-Content $geminiStderr -Raw } else { "" }
        if (-not (Test-Path $geminiOutputFile) -or (Get-Item $geminiOutputFile).Length -eq 0) {
            Write-ErrorVerdict -Reviewer "gemini" -Summary "Invocation failed (exit $($geminiProc.ExitCode)): $stderrContent" -OutputPath $geminiOutputFile
        }
        Write-Host "Gemini: FAILED (exit $($geminiProc.ExitCode))"
    } else {
        # Parse Gemini JSON envelope → extract response field
        try {
            $rawOutput = Get-Content $geminiStdout -Raw -ErrorAction Stop
            $envelope = $rawOutput | ConvertFrom-Json -ErrorAction Stop
            $content = $envelope.response
            if (-not $content) { throw "response field missing or empty" }
            # Strip markdown fences if Gemini wraps JSON in ```json ... ```
            $content = $content.Trim()
            if ($content.StartsWith('```')) {
                $content = $content -replace '(?s)^```\w*\r?\n(.*?)\r?\n```$', '$1'
                $content = $content.Trim()
            }
            $content | Set-Content $geminiOutputFile -Encoding utf8
            Write-Host "Gemini: DONE"
        } catch {
            Write-ErrorVerdict -Reviewer "gemini" -Summary "Output parse failed: $_" -OutputPath $geminiOutputFile
            Write-Host "Gemini: PARSE ERROR - $_"
        }
    }

    Write-Host ""
    Write-Host "Results written to:"
    Write-Host "  $codexOutputFile"
    Write-Host "  $geminiOutputFile"
} finally {
    # Cleanup all temp files
    foreach ($f in @($codexPromptFile, $geminiPromptFile, $codexStdout, $codexStderr, $geminiStdout, $geminiStderr)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    # Cleanup review-input temp copy if created
    $reviewInputDir = Join-Path $root "docs" "plans" ".review-input"
    if (Test-Path $reviewInputDir) {
        Remove-Item $reviewInputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
