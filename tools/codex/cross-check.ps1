param(
    [ValidateSet("errors", "endpoints", "html", "schemas", "domains", "limits", "all")]
    [string]$Area = "all"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

function Run-Area {
    param([string]$Name)
    Write-Host "== $Name =="
    switch ($Name) {
        "errors" {
            rg -n "VALIDATION_ERROR|UNAUTHORIZED|USAGE_EXCEEDED|RATE_LIMITED|CONTENT_TOO_LARGE|CONFLICT|INTERNAL_ERROR" flashcard-backend flashcard-anki flashcard-web
        }
        "endpoints" {
            rg -n "/cards/generate|/cards/enhance|/usage/current|/billing|/account/export|/assets/tts|/assets/image" flashcard-backend flashcard-anki flashcard-web
        }
        "html" {
            rg -n "fc-[a-z-]+" flashcard-backend/src/lib/prompts/hooks flashcard-anki/src/styles/stylesheet.py flashcard-web/src/components
        }
        "schemas" {
            rg -n "Generate|Enhance|usage|product_source|request_id" flashcard-backend/src/lib/validation flashcard-anki/src/api flashcard-web/src/types flashcard-web/src/lib/api.ts
        }
        "domains" {
            rg -n "lang|general|med|stem-m|stem-cs|fin|law|arts|skill|mem" flashcard-backend/src/lib/prompts/hooks flashcard-anki/src/ui flashcard-web/src
        }
        "limits" {
            rg -n "100KB|10MB|content.?size|CONTENT_TOO_LARGE" flashcard-backend flashcard-anki flashcard-web
        }
    }
    Write-Host ""
}

if ($Area -eq "all") {
    foreach ($a in @("errors", "endpoints", "html", "schemas", "domains", "limits")) { Run-Area $a }
} else {
    Run-Area $Area
}
