<#
.SYNOPSIS
    Converts ScribeHow guides to local HTML guide pages for the Learning Hub.

.DESCRIPTION
    Fetches rendered HTML from ScribeHow using Edge headless, parses steps and images,
    downloads images locally, generates HTML using the established guide template,
    writes the output file, and updates index.html with the converted guide link.

.PARAMETER Title
    Keyword to match a guide title in guides-to-convert.json (partial match, case-insensitive).

.PARAMETER All
    Convert all guides in guides-to-convert.json.

.PARAMETER DryRun
    Parse and show what would be generated without writing files.

.EXAMPLE
    .\tools\convert-guide.ps1 -Title "Bill Pay"
    .\tools\convert-guide.ps1 -All
    .\tools\convert-guide.ps1 -Title "Reset Password" -DryRun
#>

param(
    [string]$Title = "",
    [switch]$All,
    [switch]$DryRun
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$ConfigFile = Join-Path $RepoRoot "Working\guides-to-convert.json"
$IndexFile  = Join-Path $RepoRoot "index.html"
$EdgeExe    = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

if (-not (Test-Path $EdgeExe)) {
    $EdgeExe = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
}
if (-not (Test-Path $EdgeExe)) {
    Write-Error "Microsoft Edge not found. Please install Edge or update the path in this script."
    exit 1
}

# ---------------------------------------------------------------------------
# Load guide queue
# ---------------------------------------------------------------------------
if (-not (Test-Path $ConfigFile)) {
    Write-Error "guides-to-convert.json not found at: $ConfigFile"
    exit 1
}
$Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

# Flatten all guides into one list, tagging each with its section
$AllGuides = @()
foreach ($g in $Config.mobile) {
    $g | Add-Member -NotePropertyName "section" -NotePropertyValue "mobile" -Force
    $AllGuides += $g
}
foreach ($g in $Config.online) {
    $g | Add-Member -NotePropertyName "section" -NotePropertyValue "online" -Force
    $AllGuides += $g
}

# ---------------------------------------------------------------------------
# Select guides to process
# ---------------------------------------------------------------------------
$GuidesToProcess = @()

if ($All) {
    $GuidesToProcess = $AllGuides
} elseif ($Title -ne "") {
    $GuidesToProcess = $AllGuides | Where-Object { $_.title -like "*$Title*" }
    if ($GuidesToProcess.Count -eq 0) {
        Write-Host "No guide found matching: '$Title'" -ForegroundColor Yellow
        Write-Host "Available guides:" -ForegroundColor Cyan
        $AllGuides | ForEach-Object { Write-Host "  [$($_.section)] $($_.title)" }
        exit 0
    }
} else {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  .\tools\convert-guide.ps1 -Title `"<keyword>`"    # convert one guide"
    Write-Host "  .\tools\convert-guide.ps1 -All                    # convert all guides"
    Write-Host "  .\tools\convert-guide.ps1 -All -DryRun            # preview without writing"
    Write-Host ""
    Write-Host "Pending guides:" -ForegroundColor Cyan
    $AllGuides | ForEach-Object { Write-Host "  [$($_.section)] $($_.title)" }
    exit 0
}

# ---------------------------------------------------------------------------
# Helper: Fetch rendered DOM via Edge headless
# ---------------------------------------------------------------------------
function Get-RenderedDom {
    param([string]$Url)

    # Normalise: always use /viewer/ form for rendering
    # /embed/... and /shared/... both redirect, but /viewer/ gives fullest DOM
    $ViewerUrl = $Url
    if ($Url -match "scribehow\.com/shared/([^?]+)") {
        # Extract the ScribeId from the path slug (last __ segment)
        $slug = $Matches[1]
        if ($slug -match "__([A-Za-z0-9_-]+)$") {
            $scribeId = $Matches[1]
            $ViewerUrl = "https://scribehow.com/viewer/$scribeId"
        }
    } elseif ($Url -match "scribehow\.com/embed/[^_]+__([A-Za-z0-9_-]+)") {
        $scribeId = $Matches[1].Split("?")[0]
        $ViewerUrl = "https://scribehow.com/viewer/$scribeId"
    } elseif ($Url -match "scribehow\.com/viewer/[^_]+__([A-Za-z0-9_-]+)") {
        $scribeId = $Matches[1].Split("?")[0]
        $ViewerUrl = "https://scribehow.com/viewer/$scribeId"
    }

    Write-Host "  Fetching: $ViewerUrl" -ForegroundColor DarkGray

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName               = $EdgeExe
    $pinfo.Arguments              = "--headless --disable-gpu --dump-dom `"$ViewerUrl`""
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError  = $true
    $pinfo.UseShellExecute        = $false
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $dom  = $proc.StandardOutput.ReadToEnd()
    $null = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return $dom
}

# ---------------------------------------------------------------------------
# Helper: Extract text content from an HTML snippet (strip tags)
# ---------------------------------------------------------------------------
function Strip-Html {
    param([string]$html)
    return [System.Text.RegularExpressions.Regex]::Replace($html, "<[^>]+>", "") `
        -replace "&amp;",  "&" `
        -replace "&lt;",   "<" `
        -replace "&gt;",   ">" `
        -replace "&nbsp;", " " `
        -replace "&quot;", '"' `
        -replace "&#39;",  "'" `
        -replace "\s{2,}", " "
}

# ---------------------------------------------------------------------------
# Helper: Extract the inner HTML of the first element matching a regex pattern
# ---------------------------------------------------------------------------
function Get-InnerHtml {
    param([string]$dom, [string]$pattern)
    if ($dom -match $pattern) {
        return $Matches[1]
    }
    return ""
}

# ---------------------------------------------------------------------------
# Helper: Download an image and return local relative path
# ---------------------------------------------------------------------------
function Download-Image {
    param(
        [string]$ImageUrl,
        [string]$SaveDir,
        [string]$FileName
    )
    if ([string]::IsNullOrWhiteSpace($ImageUrl)) { return "" }

    try {
        $null = New-Item -ItemType Directory -Path $SaveDir -Force
        $savePath = Join-Path $SaveDir $FileName
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($ImageUrl, $savePath)
        Write-Host "    Downloaded: $FileName" -ForegroundColor DarkGray
        return $savePath
    } catch {
        Write-Host "    WARNING: Failed to download image: $ImageUrl" -ForegroundColor Yellow
        Write-Host "    Error: $_" -ForegroundColor DarkGray
        return ""
    }
}

# ---------------------------------------------------------------------------
# Helper: Generate slug from outputFile path
#   "guides/mobile/add-biller-pay-bills.html" -> "add-biller-pay-bills"
# ---------------------------------------------------------------------------
function Get-Slug {
    param([string]$outputFile)
    return [System.IO.Path]::GetFileNameWithoutExtension($outputFile)
}

# ---------------------------------------------------------------------------
# Helper: Determine image subfolder name from outputFile
#   "guides/mobile/add-biller-pay-bills.html" -> "add-biller-pay-bills"
# ---------------------------------------------------------------------------
function Get-ImageFolder {
    param([string]$outputFile)
    return Get-Slug $outputFile
}

# ---------------------------------------------------------------------------
# Core parse function: extract steps, tips, warnings from rendered DOM
# ---------------------------------------------------------------------------
function Parse-ScribeDom {
    param([string]$dom, [string]$guideTitle)

    $result = @{
        Title       = $guideTitle
        Description = ""
        Items       = @()   # array of hashtables: type, number, text, imageUrl, tipType
    }

    # --- Title from DOM (override if found) ---
    if ($dom -match 'data-testid="document-title"[^>]*>([^<]+)<') {
        $result.Title = $Matches[1].Trim()
    }

    # --- Description ---
    if ($dom -match 'class="whitespace-pre-wrap[^"]*"[^>]*>([\s\S]*?)</') {
        $raw = $Matches[1]
        $result.Description = (Strip-Html $raw).Trim()
    }

    # --- Steps ---
    # Each step is wrapped in a block with data-testid="action-instruction"
    # We iterate by splitting on this marker
    $stepPattern  = 'data-testid="action-instruction"'
    $tipPattern   = 'data-testid="action-tip-or-warning"'

    # Split dom around action blocks to preserve order
    # We'll use a combined approach: find all action blocks in document order
    $actionRegex = [regex]'data-testid="(action-instruction|action-tip-or-warning)"[\s\S]*?(?=data-testid="(?:action-instruction|action-tip-or-warning)"|$)'

    # Because the DOM is large and nested, use a simpler line-by-line scan approach
    # Walk through looking for testid markers
    $lines = $dom -split "`n"
    $currentBlock  = @()
    $blockType     = ""
    $stepNumber    = 0
    $items         = [System.Collections.Generic.List[hashtable]]::new()

    $inBlock       = $false
    $depth         = 0

    # We'll collect raw text segments between recognisable markers
    # Strategy: find all occurrences of the testid attrs and grab surrounding context
    $allMatches = [regex]::Matches($dom, '(?s)(<[^>]*data-testid="(action-instruction|action-tip-or-warning)"[^>]*>)([\s\S]{0,8000}?)(?=<[^>]*data-testid="(?:action-instruction|action-tip-or-warning)"|</main>|</article>|<footer)')

    foreach ($m in $allMatches) {
        $blockContent = $m.Groups[3].Value
        $testId       = $m.Groups[2].Value

        if ($testId -eq "action-instruction") {
            $stepNumber++
            $item = @{
                type     = "step"
                number   = $stepNumber
                text     = ""
                listItems = @()
                imageUrl = ""
            }

            # Extract step text - look for the instruction text elements
            # Pattern: spans/divs containing the step instruction text
            $textMatch = [regex]::Match($blockContent, '(?s)<p\b[^>]*>([\s\S]*?)</p>')
            if (-not $textMatch.Success) {
                $textMatch = [regex]::Match($blockContent, '(?s)<span\b[^>]*class="[^"]*(?:prose|instruction|step-text|action-text)[^"]*"[^>]*>([\s\S]*?)</span>')
            }
            if (-not $textMatch.Success) {
                # Grab first substantial text node
                $textMatch = [regex]::Match($blockContent, '(?s)<(?:div|span|p)\b[^>]*>([\s\S]*?)</(?:div|span|p)>')
            }

            $rawText = if ($textMatch.Success) { $textMatch.Groups[1].Value } else { "" }
            $item.text = (Strip-Html $rawText).Trim()

            # Extract image URL (src from img tags within the block)
            $imgMatch = [regex]::Match($blockContent, '(?i)<img\b[^>]*\bsrc="([^"]+)"')
            if ($imgMatch.Success) {
                $item.imageUrl = $imgMatch.Groups[1].Value
            }

            $items.Add($item)

        } elseif ($testId -eq "action-tip-or-warning") {
            $item = @{
                type    = "card"
                cardType = "tip"
                text    = ""
            }

            # Determine if warning or tip/info
            # Warning indicators: "warning", "alert", exclamation in content or class
            if ($blockContent -match '(?i)(warning|alert|caution|danger|bi-exclamation|exclamation)') {
                $item.cardType = "warning"
            }

            # Extract text
            $textMatch = [regex]::Match($blockContent, '(?s)<p\b[^>]*>([\s\S]*?)</p>')
            if (-not $textMatch.Success) {
                $textMatch = [regex]::Match($blockContent, '(?s)<(?:div|span)\b[^>]*>([\s\S]*?)</(?:div|span)>')
            }
            $rawText = if ($textMatch.Success) { $textMatch.Groups[1].Value } else { $blockContent }
            $item.text = (Strip-Html $rawText).Trim()

            if ($item.text.Length -gt 5) {
                $items.Add($item)
            }
        }
    }

    # Fallback: if no items found, try a simpler text extraction
    if ($items.Count -eq 0) {
        Write-Host "  WARNING: Standard DOM parse found no steps. Trying fallback extraction..." -ForegroundColor Yellow

        # Look for numbered step patterns in raw text
        $stripped = Strip-Html $dom
        $stepMatches = [regex]::Matches($stripped, '(?m)^\s*(\d+)\.\s+(.+)$')
        $stepNum = 0
        foreach ($sm in $stepMatches) {
            $stepNum++
            $items.Add(@{
                type     = "step"
                number   = $stepNum
                text     = $sm.Groups[2].Value.Trim()
                listItems = @()
                imageUrl = ""
            })
        }
    }

    $result.Items = $items
    return $result
}

# ---------------------------------------------------------------------------
# Helper: Escape HTML special chars for attribute/content use
# ---------------------------------------------------------------------------
function Escape-Html {
    param([string]$s)
    return $s -replace "&", "&amp;" -replace "<", "&lt;" -replace ">", "&gt;" -replace '"', "&quot;"
}

# ---------------------------------------------------------------------------
# Generate guide HTML from parsed data
# ---------------------------------------------------------------------------
function Generate-GuideHtml {
    param(
        [hashtable]$Parsed,
        [string]$Slug,
        [string]$Section   # "mobile" or "online"
    )

    $title       = $Parsed.Title
    $description = $Parsed.Description
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = "This guide walks you through the steps for: $title."
    }

    $stepsHtml = [System.Text.StringBuilder]::new()

    foreach ($item in $Parsed.Items) {
        if ($item.type -eq "step") {
            $numStr   = $item.number.ToString()
            $stepText = Escape-Html $item.text

            # Build image block
            $imageBlock = ""
            if (-not [string]::IsNullOrWhiteSpace($item.imageUrl)) {
                $imgNum    = $item.number.ToString("D2")
                $imgPath   = "../../images/guides/$Slug/step-$imgNum.webp"
                $altText   = Escape-Html "Step $($item.number): $($item.text.Substring(0, [Math]::Min(60, $item.text.Length)))"
                $imageBlock = @"

            <div class="step-image">
                    <div class="image-container">
                        <img src="$imgPath" alt="$altText">
                    </div>
                </div>
"@
            }

            $null = $stepsHtml.Append(@"

            <!-- Step $numStr -->
            <div class="step-card">
                <div class="step-header">
                    <span class="step-number">$numStr</span>
                    <div class="step-text">
                        <strong>$stepText</strong>
                    </div>
                </div>$imageBlock
            </div>
"@)

        } elseif ($item.type -eq "card") {
            $cardText = Escape-Html $item.text
            if ($item.cardType -eq "warning") {
                $null = $stepsHtml.Append(@"

            <!-- Warning -->
            <div class="warning-card">
                <i class="bi bi-exclamation-triangle-fill card-icon"></i>
                <div class="warning-text">
                    <strong>$cardText</strong>
                </div>
            </div>
"@)
            } else {
                $null = $stepsHtml.Append(@"

            <!-- Tip -->
            <div class="tip-card">
                <i class="bi bi-info-circle-fill card-icon"></i>
                <div class="tip-text">
                    <strong>$cardText</strong>
                </div>
            </div>
"@)
            }
        }
    }

    $htmlTitle   = Escape-Html "$title | CW Banking Guide"
    $h1Title     = Escape-Html $title
    $descHtml    = Escape-Html $description

    $navClass = if ($Section -eq "mobile") { "mobile-topnav" } else { "guide-topnav" }

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$htmlTitle</title>
    <link rel="stylesheet" href="../../css/guide.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.css">
</head>
<body>
    <nav class="$navClass">
        <a href="../../index.html">
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg>
            Back to All Guides
        </a>
    </nav>
    <div class="container">
        <div class="header">
            <div class="icon-wrapper">
                <div class="icon-circle">
                    <img src="https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://centralwcu.org&size=64" alt="Central Willamette CU">
                </div>
            </div>
            <div class="header-content">
                <h1>$h1Title</h1>
                <p class="description">$descHtml</p>
            </div>
        </div>
        
        <div class="steps">$($stepsHtml.ToString())
        </div>
    </div>
</body>
</html>
"@
}

# ---------------------------------------------------------------------------
# Update index.html: replace guide-pending anchor with local link
# ---------------------------------------------------------------------------
function Update-IndexHtml {
    param(
        [string]$GuideTitle,
        [string]$OutputFile,   # e.g. "guides/mobile/add-biller-pay-bills.html"
        [string]$Keywords,
        [string]$ScribeUrl
    )

    $indexContent = Get-Content $IndexFile -Raw -Encoding UTF8

    # Build the replacement <a> tag (no guide-pending class, no external href)
    $escapedTitle = $GuideTitle -replace "&", "&amp;"
    $newAnchor = "href=`"$OutputFile`"`r`n                  data-keywords=`"$Keywords`">`r`n                  $escapedTitle`r`n                </a>"

    # We need to find existing anchors that reference this scribeUrl
    # Match pattern: href="<scribeUrl>..." with guide-pending class
    $escapedUrl = [regex]::Escape($ScribeUrl.Split("?")[0])

    # Regex to match the full <a ...> tag block referencing this Scribe URL
    # Handles both desktop and mobile-only sections (replace all occurrences)
    $anchorRegex = [regex]'(?s)(<a\s[^>]*?class="[^"]*?guide-pending[^"]*?"[^>]*?href="[^"]*?' + [regex]::Escape($ScribeUrl.Split("?")[0]) + '[^"]*?"[\s\S]*?>)([\s\S]*?)(</a>)'

    $matches = $anchorRegex.Matches($indexContent)
    if ($matches.Count -eq 0) {
        Write-Host "  WARNING: Could not find pending anchor for '$GuideTitle' in index.html" -ForegroundColor Yellow
        Write-Host "           Searched for URL fragment: $($ScribeUrl.Split('?')[0])" -ForegroundColor DarkGray
        return
    }

    $updated = $anchorRegex.Replace($indexContent, {
        param($m)
        # Preserve the opening tag structure but replace class and href
        $originalTag = $m.Groups[1].Value
        $innerText   = $m.Groups[2].Value.Trim()

        # Build new opening tag: remove guide-pending, target, rel; update href
        $newTag = $originalTag
        # Remove guide-pending from class
        $newTag = [regex]::Replace($newTag, '\s*guide-pending\s*', ' ')
        # Remove target="_blank" rel="noopener"
        $newTag = [regex]::Replace($newTag, '\s*target="_blank"\s*', ' ')
        $newTag = [regex]::Replace($newTag, '\s*rel="noopener"\s*', ' ')
        # Replace href with local path
        $newTag = [regex]::Replace($newTag, 'href="[^"]*"', "href=`"$OutputFile`"")
        # Clean up double spaces in class attr
        $newTag = [regex]::Replace($newTag, 'class="([^"]*?)\s{2,}([^"]*?)"', 'class="$1 $2"')
        $newTag = $newTag.TrimEnd()

        return "$newTag`r`n                  $innerText`r`n                </a>"
    })

    if ($updated -eq $indexContent) {
        Write-Host "  WARNING: Replacement made no change in index.html for '$GuideTitle'" -ForegroundColor Yellow
    } else {
        $changeCount = $matches.Count
        Write-Host "  Updated $changeCount occurrence(s) in index.html" -ForegroundColor Green
    }

    if (-not $DryRun) {
        Set-Content -Path $IndexFile -Value $updated -Encoding UTF8 -NoNewline
    }
}

# ---------------------------------------------------------------------------
# Remove converted guide from guides-to-convert.json
# ---------------------------------------------------------------------------
function Remove-FromQueue {
    param([string]$OutputFile, [string]$Section)

    $json = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $remaining = $json.$Section | Where-Object { $_.outputFile -ne $OutputFile }
    $json.$Section = $remaining

    if (-not $DryRun) {
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile -Encoding UTF8
        Write-Host "  Removed from guides-to-convert.json" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Process a single guide entry
# ---------------------------------------------------------------------------
function Convert-Guide {
    param([PSCustomObject]$Guide)

    $title      = $Guide.title
    $outputFile = $Guide.outputFile   # e.g. "guides/mobile/add-biller-pay-bills.html"
    $scribeUrl  = $Guide.scribeUrl
    $keywords   = $Guide.keywords
    $section    = $Guide.section

    $slug       = Get-Slug $outputFile
    $imageFolder = Get-ImageFolder $outputFile
    $outputPath = Join-Path $RepoRoot $outputFile
    $imageDir   = Join-Path $RepoRoot "images\guides\$imageFolder"

    Write-Host ""
    Write-Host "Converting: $title" -ForegroundColor Cyan
    Write-Host "  Output:   $outputFile"
    Write-Host "  Images:   images/guides/$imageFolder/"

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would fetch, parse and write $outputFile" -ForegroundColor DarkYellow
    }

    # 1. Fetch DOM
    $dom = Get-RenderedDom $scribeUrl

    if ($dom.Length -lt 1000) {
        Write-Host "  WARNING: DOM response seems too small ($($dom.Length) bytes). The page may not have rendered correctly." -ForegroundColor Yellow
        Write-Host "  Continuing with available content..." -ForegroundColor DarkGray
    }

    # 2. Parse DOM
    $parsed = Parse-ScribeDom -dom $dom -guideTitle $title

    Write-Host "  Parsed: $($parsed.Items.Count) items ($(@($parsed.Items | Where-Object { $_.type -eq 'step' }).Count) steps, $(@($parsed.Items | Where-Object { $_.type -eq 'card' }).Count) cards)"

    if ($parsed.Items.Count -eq 0) {
        Write-Host "  ERROR: No content parsed from DOM. Skipping $title." -ForegroundColor Red
        Write-Host "         You may need to manually convert this guide." -ForegroundColor DarkGray
        return
    }

    # 3. Download images (immediately — signed URLs expire ~15 min)
    $stepItems = @($parsed.Items | Where-Object { $_.type -eq "step" -and -not [string]::IsNullOrWhiteSpace($_.imageUrl) })
    if ($stepItems.Count -gt 0) {
        Write-Host "  Downloading $($stepItems.Count) image(s)..." -ForegroundColor DarkGray
        foreach ($item in $stepItems) {
            $imgNum  = $item.number.ToString("D2")
            $imgFile = "step-$imgNum.webp"
            if (-not $DryRun) {
                Download-Image -ImageUrl $item.imageUrl -SaveDir $imageDir -FileName $imgFile | Out-Null
            } else {
                Write-Host "    [DRY RUN] Would download: $imgFile from $($item.imageUrl.Substring(0,[Math]::Min(80,$item.imageUrl.Length)))..." -ForegroundColor DarkYellow
            }
        }
    } else {
        Write-Host "  No images found in parsed content." -ForegroundColor DarkGray
    }

    # 4. Generate HTML
    $html = Generate-GuideHtml -Parsed $parsed -Slug $imageFolder -Section $section

    # 5. Write output file
    if (-not $DryRun) {
        $null = New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force
        Set-Content -Path $outputPath -Value $html -Encoding UTF8 -NoNewline
        Write-Host "  Written: $outputFile" -ForegroundColor Green
    } else {
        Write-Host "  [DRY RUN] Would write: $outputFile ($($html.Length) chars)" -ForegroundColor DarkYellow
    }

    # 6. Update index.html
    Write-Host "  Updating index.html..." -ForegroundColor DarkGray
    Update-IndexHtml -GuideTitle $title -OutputFile $outputFile -Keywords $keywords -ScribeUrl $scribeUrl

    # 7. Remove from queue
    if (-not $DryRun) {
        Remove-FromQueue -OutputFile $outputFile -Section $section
    }

    Write-Host "  Done: $title" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Learning Hub Guide Converter" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "DRY RUN MODE - no files will be written" -ForegroundColor DarkYellow
}
Write-Host "Guides to process: $($GuidesToProcess.Count)"
Write-Host ""

$successCount = 0
$failCount    = 0

foreach ($guide in $GuidesToProcess) {
    try {
        Convert-Guide -Guide $guide
        $successCount++
    } catch {
        Write-Host "  ERROR processing '$($guide.title)': $_" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "============================" -ForegroundColor Cyan
Write-Host "Complete: $successCount succeeded, $failCount failed" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
if (-not $DryRun -and $successCount -gt 0) {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Open each generated guide in a browser and verify the content looks correct."
    Write-Host "  2. Check images rendered at the right steps."
    Write-Host "  3. Commit and push when satisfied."
}
