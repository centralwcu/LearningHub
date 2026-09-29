<#
.SYNOPSIS
    Converts .docx guide files in Working/Markdown/New to local HTML guide pages for the Learning Hub.

.DESCRIPTION
    Scans Working/Markdown/New subfolders for .docx files, extracts markdown content,
    downloads images locally, generates HTML using the established guide template,
    writes the output file, updates index.html, and moves each .docx to
    Working/Markdown/Worked when done.

    Subfolder name determines the section: Mobile -> mobile, OLB -> online.

.PARAMETER DryRun
    Parse and show what would be generated without writing files.

.EXAMPLE
    .\tools\convert-guide.ps1
    .\tools\convert-guide.ps1 -DryRun
#>

param(
    [switch]$DryRun
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Web

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$RepoRoot          = Split-Path $PSScriptRoot -Parent
$ConfigFile        = Join-Path $RepoRoot "Working\guides-to-convert.json"
$IndexFile         = Join-Path $RepoRoot "index.html"
$MarkdownNewDir    = Join-Path $RepoRoot "Working\Markdown\New"
$MarkdownWorkedDir = Join-Path $RepoRoot "Working\Markdown\Worked"

# ---------------------------------------------------------------------------
# Load guides-to-convert.json for title/keyword matching against pending entries
# ---------------------------------------------------------------------------
$AllGuides = @()
if (Test-Path $ConfigFile) {
    $Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    foreach ($g in $Config.mobile) {
        $g | Add-Member -NotePropertyName "section" -NotePropertyValue "mobile" -Force
        $AllGuides += $g
    }
    foreach ($g in $Config.online) {
        $g | Add-Member -NotePropertyName "section" -NotePropertyValue "online" -Force
        $AllGuides += $g
    }
}

# ---------------------------------------------------------------------------
# Helper: Extract raw markdown text from a .docx file via <w:t> XML nodes
# ---------------------------------------------------------------------------
function Get-DocxText {
    param([string]$DocxPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip   = [System.IO.Compression.ZipFile]::OpenRead($DocxPath)
    $entry = $zip.Entries | Where-Object { $_.FullName -eq "word/document.xml" }
    if (-not $entry) {
        $zip.Dispose()
        Write-Error "word/document.xml not found inside: $DocxPath"
        return ""
    }
    $reader  = New-Object System.IO.StreamReader($entry.Open())
    $xml     = $reader.ReadToEnd()
    $reader.Close()
    $zip.Dispose()

    # Split the XML on paragraph boundaries, collect text runs within each paragraph,
    # then join paragraphs with newlines so the step regex can match line by line.
    $paragraphs = [regex]::Split($xml, '</w:p>')
    $lines = foreach ($para in $paragraphs) {
        $runs = [regex]::Matches($para, '<w:t(?:\s[^>]*)?>([^<]*)</w:t>')
        if ($runs.Count -gt 0) {
            ($runs | ForEach-Object { $_.Groups[1].Value }) -join ""
        }
    }
    return ($lines | Where-Object { $_ -ne $null -and $_ -ne "" }) -join "`n"
}

# ---------------------------------------------------------------------------
# Helper: Parse raw markdown text (from docx) into the $parsed structure
# used by Generate-GuideHtml
# ---------------------------------------------------------------------------
function Parse-DocxMarkdown {
    param([string]$markdownText, [string]$docxFileName)

    # Title is ALWAYS the docx filename stem — never the # heading inside the file
    $result = @{
        Title       = [System.IO.Path]::GetFileNameWithoutExtension($docxFileName)
        Description = ""
        Items       = [System.Collections.Generic.List[hashtable]]::new()
    }

    # Decode HTML entities (docx may contain &amp; etc.)
    $text = [System.Web.HttpUtility]::HtmlDecode($markdownText)

    # Skip past any leading # heading (we ignore its text — filename is authoritative)
    if ($text -match '(?m)^#+\s+(.+)') {
        $text = $text.Substring($Matches[0].Length).TrimStart()
    }

    # Identify step lines: "N\. **text**" optionally followed by "![...](url)"
    # Everything before the first step line is the description
    $firstStepMatch = [regex]::Match($text, '(?m)^\d+\\?\.\s')
    if ($firstStepMatch.Success -and $firstStepMatch.Index -gt 0) {
        $descBlock = $text.Substring(0, $firstStepMatch.Index)
        $text = $text.Substring($firstStepMatch.Index)

        # Extract Tip:/Alert: lines from the description block into pre-step cards.
        # Everything before the first Tip:/Alert: line becomes the plain description text.
        $descLines = $descBlock -split "`n"
        $descTextLines  = [System.Collections.Generic.List[string]]::new()
        $preStepCards   = [System.Collections.Generic.List[hashtable]]::new()
        $inCard = $false
        $cardType = ""
        $cardHeader = ""
        $cardLines = [System.Collections.Generic.List[string]]::new()

        foreach ($dl in $descLines) {
            $dlt = $dl.Trim()
            if ($dlt -match '^(Tip|Alert):\s*(.*)$') {
                # Flush any in-progress card
                if ($inCard -and ($cardLines.Count -gt 0 -or $cardHeader -ne '')) {
                    $headerLine = $cardHeader -replace '\*+', ''
                    # Only lines starting with - or * become list items; others append to text
                    $bullets = @($cardLines | Where-Object { $_ -match '^[-*]\s' } | ForEach-Object { $_ -replace '^[-*]\s*', '' -replace '\*+', '' })
                    $plainText = @($cardLines | Where-Object { $_ -notmatch '^[-*]\s' } | ForEach-Object { $_ -replace '\*+', '' })
                    if ($plainText.Count -gt 0) {
                        $headerLine += ' ' + (($plainText -join ' ').Trim())
                    }
                    $preStepCards.Add(@{ cardType = $cardType; text = $headerLine; listItems = $bullets })
                    $cardLines.Clear()
                    $cardHeader = ''
                }
                $inCard = $true
                $cardType = if ($Matches[1] -eq 'Alert') { 'warning' } else { 'tip' }
                $cardHeader = $Matches[2].Trim()
            } elseif ($inCard) {
                # Continuation of card text (e.g. bullet lines that belong to the tip)
                if ($dlt -ne '') { $cardLines.Add($dlt) }
            } else {
                # Strip bare markdown headings (#### ...) that leaked into the description
                if ($dlt -notmatch '^#{1,6}\s') {
                    $descTextLines.Add($dl)
                }
            }
        }
        # Flush final card if open
        if ($inCard -and ($cardLines.Count -gt 0 -or $cardHeader -ne '')) {
            $headerLine = $cardHeader -replace '\*+', ''
            # Only lines starting with - or * become list items; others append to text
            $bullets = @($cardLines | Where-Object { $_ -match '^[-*]\s' } | ForEach-Object { $_ -replace '^[-*]\s*', '' -replace '\*+', '' })
            $plainText = @($cardLines | Where-Object { $_ -notmatch '^[-*]\s' } | ForEach-Object { $_ -replace '\*+', '' })
            if ($plainText.Count -gt 0) {
                $headerLine += ' ' + (($plainText -join ' ').Trim())
            }
            $preStepCards.Add(@{ cardType = $cardType; text = $headerLine; listItems = $bullets })
        }

        $result.Description = ($descTextLines -join "`n").Trim()

        # Emit pre-step cards as Items
        foreach ($pc in $preStepCards) {
            $result.Items.Add(@{
                type      = "card"
                cardType  = $pc.cardType
                text      = $pc.text
                listItems = $pc.listItems
                imageUrl  = ""
            })
        }
    }

    # Each step is on its own line:  N\. **step text**
    # Tip:/Alert: lines between steps become card items.
    # The image (if any) is on the very next non-empty line: ![](url)
    # Multi-line step text ends at the first image/card/next-step line.
    $textLines = $text -split "`n"
    $i = 0
    while ($i -lt $textLines.Count) {
        $line = $textLines[$i].Trim()

        # Card line between steps: Tip: or Alert: **text**
        # May be followed by bullet lines on subsequent lines
        if ($line -match '^(Tip|Alert):\s*(.*)$') {
            $cardType   = if ($Matches[1] -eq 'Alert') { 'warning' } else { 'tip' }
            $cardHeader = $Matches[2].Trim() -replace '\*+', ''
            $cardBullets = [System.Collections.Generic.List[string]]::new()
            $j = $i + 1
            while ($j -lt $textLines.Count) {
                $nxt = $textLines[$j].Trim()
                if ($nxt -eq '') { $j++; break }
                if ($nxt -match '^(Tip|Alert):') { break }
                if ($nxt -match '^\d+\\?\.\s') { break }
                if ($nxt -match '^!\[') { break }
                $cardBullets.Add(($nxt -replace '^[-*]\s*', '' -replace '\*+', '').Trim())
                $j++
            }
            $i = $j - 1
            $result.Items.Add(@{
                type      = "card"
                cardType  = $cardType
                text      = $cardHeader
                listItems = @($cardBullets)
                imageUrl  = ""
            })
            $i++
            continue
        }

        # Step line: N\. **text** (bold markers optional — step text may not be wrapped in **)
        if ($line -match '^(\d+)\\?\.\s+\*{0,2}(.+?)\*{0,2}\\?\s*$') {
            $stepNum  = [int]$Matches[1]
            $stepText = $Matches[2].Trim()
            $imageUrl = ""

            # Collect continuation lines (backslash-terminated or plain text)
            # until we hit an image line, a card line, the next step, or empty line
            $j = $i + 1
            while ($j -lt $textLines.Count) {
                $nxt = $textLines[$j].Trim()
                if ($nxt -eq '') { $j++; break }
                if ($nxt -match '^!\[') { break }
                if ($nxt -match '^(Tip|Alert):') { break }
                if ($nxt -match '^\d+\\?\.\s') { break }
                # Strip trailing backslash continuation marker
                $stepText += ' ' + ($nxt -replace '\\$', '').Trim()
                $j++
            }
            $stepText = $stepText.Trim() -replace '\*+', '' -replace '\s+', ' '

            # Look ahead for image
            while ($j -lt $textLines.Count -and $textLines[$j].Trim() -eq '') { $j++ }
            if ($j -lt $textLines.Count -and $textLines[$j].Trim() -match '^!\[.*?\]\(([^)]+)\)') {
                $imageUrl = $Matches[1].Trim()
                $i = $j  # consume the image line
            } else {
                $i = $j - 1  # back up so outer loop doesn't skip a line
            }

            $result.Items.Add(@{
                type      = "step"
                number    = $stepNum
                text      = $stepText
                listItems = @()
                imageUrl  = $imageUrl
            })
        }
        $i++
    }

    return $result
}

# ---------------------------------------------------------------------------
# Helper: Map a New subfolder name to a guide section name
#   "Mobile" -> "mobile"   "OLB" -> "online"
# ---------------------------------------------------------------------------
function Get-SectionFromFolder {
    param([string]$folderName)
    switch ($folderName.ToLower()) {
        "mobile" { return "mobile" }
        "olb"    { return "online" }
        default  { return $folderName.ToLower() }
    }
}

# ---------------------------------------------------------------------------
# Helper: Derive outputFile path from title and section
#   e.g. "Delete Saved Billers" + "mobile" -> "guides/mobile/delete-saved-billers.html"
# ---------------------------------------------------------------------------
function Get-OutputFileFromTitle {
    param([string]$title, [string]$section)
    $slug = $title.ToLower() `
        -replace '[^a-z0-9\s-]', '' `
        -replace '\s+', '-' `
        -replace '-{2,}', '-'
    return "guides/$section/$slug.html"
}

# ---------------------------------------------------------------------------
# Helper: Generate search keywords from a guide title and section.
# Produces a comma-separated keyword string modelled on the existing index entries.
# ---------------------------------------------------------------------------
function Generate-Keywords {
    param([string]$title, [string]$section)

    # Base keywords are all individual title words (lower-cased, length > 2)
    $words = $title -split '\s+' | Where-Object { $_.Length -gt 2 } | ForEach-Object { $_.ToLower() -replace '[^a-z0-9]','' } | Where-Object { $_ -ne '' }

    $keywords = [System.Collections.Generic.List[string]]::new()

    # Always include the full title as a keyword phrase
    $keywords.Add($title.ToLower())

    # Section-specific base terms
    if ($section -eq "mobile") {
        $keywords.Add("mobile app")
        $keywords.Add("mobile banking")
        $keywords.Add("digital banking")
    } else {
        $keywords.Add("online banking")
        $keywords.Add("digital banking")
    }

    # Keyword synonyms keyed on common title words
    $synonymMap = @{
        "transfer"   = @("transfer funds", "move money", "move funds")
        "payment"    = @("make payment", "schedule payment", "scheduled payment")
        "scheduled"  = @("scheduled", "edit scheduled", "cancel scheduled")
        "edit"       = @("edit", "update", "modify", "change")
        "cancel"     = @("cancel", "delete", "remove")
        "delete"     = @("delete", "remove", "manage")
        "external"   = @("external account", "other bank", "outside account", "ACH")
        "internal"   = @("internal transfer", "between accounts", "CWCU account")
        "loan"       = @("loan payment", "checking to loan", "pay loan")
        "bill"       = @("bill pay", "pay bills", "biller", "payee")
        "biller"     = @("bill pay", "biller management", "payee", "manage billers")
        "person"     = @("person-to-person", "P2P", "send money", "pay someone")
        "people"     = @("person-to-person", "P2P", "manage payees", "remove person")
        "account"    = @("account management", "manage accounts")
        "unlock"     = @("locked out", "regain access", "account locked", "account help", "login issues")
        "password"   = @("reset password", "forgot password", "password help", "login help", "credentials")
        "username"   = @("forgot username", "recover username", "login help", "credentials")
        "deposit"    = @("mobile deposit", "check deposit", "remote deposit", "deposit funds")
        "statement"  = @("eStatements", "view statements", "account history", "paperless")
        "estatement" = @("eStatements", "view statements", "account history", "paperless")
        "default"    = @("settings", "preferences", "manage", "configure")
        "change"     = @("update", "modify", "edit")
        "save"       = @("saved", "manage saved", "stored")
        "add"        = @("add", "link", "connect", "set up")
    }

    foreach ($word in $words) {
        if ($synonymMap.ContainsKey($word)) {
            foreach ($syn in $synonymMap[$word]) {
                if (-not $keywords.Contains($syn)) {
                    $keywords.Add($syn)
                }
            }
        }
    }

    # Add individual meaningful title words as standalone keywords
    foreach ($word in $words) {
        if ($word.Length -gt 3 -and -not $keywords.Contains($word)) {
            $keywords.Add($word)
        }
    }

    return ($keywords | Select-Object -Unique) -join ", "
}

# ---------------------------------------------------------------------------
# Helper: Determine the category header name for a guide title and section.
# Returns the matching guide-category-title text used in index.html.
# ---------------------------------------------------------------------------
function Get-CategoryHeader {
    param([string]$Title, [string]$Section)
    $t = $Title.ToLower()

    if ($Section -eq "mobile") {
        if ($t -match 'unlock|retrieve user|reset password|user id|estatement') { return "Account Services" }
        if ($t -match 'deposit')                                                  { return "Deposits" }
        if ($t -match 'bill|biller')                                              { return "Bill Pay" }
        if ($t -match '\bperson\b|people|p2p')                                   { return "Person-to-Person Payments" }
        if ($t -match 'external')                                                 { return "External Transfers" }
        if ($t -match 'internal|loan payment')                                    { return "Internal Transfers" }
        return "Getting Started"
    } else {
        if ($t -match 'unlock|retrieve user|reset password|user id|estatement|various forms') { return "Account Services" }
        if ($t -match 'bill|biller')                                                           { return "Bill Pay" }
        if ($t -match '\bperson\b|people|p2p')                                                { return "Person-to-Person Payments" }
        if ($t -match 'external')                                                              { return "External Transfers" }
        if ($t -match 'internal|loan payment')                                                 { return "Internal Transfers" }
        if ($t -match 'open.*account|credit card|registering')                                 { return "Account Management" }
        return "Getting Started"
    }
}

# ---------------------------------------------------------------------------
# Helper: Find insertion index for a new <li> at the end of a named category
# group within a section's guide list. Returns -1 if not found (caller falls back).
# ---------------------------------------------------------------------------
function Get-CategoryInsertPosition {
    param(
        [string]$Content,
        [string]$SectionId,
        [string]$CategoryName
    )

    # Locate the section
    $sectionStart = $Content.IndexOf("id=`"$SectionId`"")
    if ($sectionStart -lt 0) { return -1 }

    # Locate the section's closing </ul>
    $ulClose = $Content.IndexOf("</ul>", $sectionStart)
    if ($ulClose -lt 0) { return -1 }

    # Search for the category header by its unique closing-span pattern
    $sectionSlice = $Content.Substring($sectionStart, $ulClose - $sectionStart)
    $catMarker    = "$CategoryName</span>"
    $catIdx       = $sectionSlice.IndexOf($catMarker)
    if ($catIdx -lt 0) { return -1 }

    # From after the category name, find the next guide-category-header (if any)
    $searchFrom       = $sectionStart + $catIdx + $catMarker.Length
    $nextHeaderAbsIdx = $Content.IndexOf("guide-category-header", $searchFrom)

    if ($nextHeaderAbsIdx -lt 0 -or $nextHeaderAbsIdx -ge $ulClose) {
        # Last category in section — insert before </ul>
        return $ulClose
    }

    # Walk back to the opening <li of the next category header
    $liTagStart = $Content.LastIndexOf("<li", $nextHeaderAbsIdx)
    if ($liTagStart -lt 0 -or $liTagStart -le $sectionStart) { return $ulClose }

    # Insert just before the whitespace-indented line that starts the next <li>
    $priorNl = $Content.LastIndexOf("`n", $liTagStart - 1)
    if ($priorNl -lt 0 -or $priorNl -le $sectionStart) { return $liTagStart }
    return $priorNl + 1
}

# ---------------------------------------------------------------------------
# Helper: Add a brand-new guide entry to index.html (no existing pending anchor)
# Inserts a new <li> under the correct category header in each section list.
# ---------------------------------------------------------------------------
function Add-ToIndexHtml {
    param(
        [string]$GuideTitle,
        [string]$OutputFile,
        [string]$Keywords,
        [string]$Section
    )

    $indexContent = Get-Content $IndexFile -Raw -Encoding UTF8
    $escapedTitle = $GuideTitle -replace "&", "&amp;"

    $newLi = @"
              <li class="list-group-item">`r`n                <a class="btn btn-link text-decoration-none p-0" href="$OutputFile"`r`n                  data-keywords="$Keywords">`r`n                  $escapedTitle`r`n                </a>`r`n              </li>
"@

    # Determine the section IDs to update.
    # Mobile guides appear in both the desktop section (mobileBankingContent) and
    # the mobile-only section (mobileBankingContentMobile). Online guides appear in
    # both onlineBankingContent and onlineBankingContentMobile.
    if ($Section -eq "mobile") {
        $sectionIds = @("mobileBankingContent", "mobileBankingContentMobile")
    } else {
        $sectionIds = @("onlineBankingContent", "onlineBankingContentMobile")
    }

    # Determine the correct category header for this guide
    $categoryHeader = Get-CategoryHeader -Title $GuideTitle -Section $Section
    Write-Host "  Category: $categoryHeader" -ForegroundColor DarkGray

    $updatedContent = $indexContent
    $anyInserted = $false

    foreach ($sectionId in $sectionIds) {
        # Find the first </ul> inside the target section collapse div
        $sectionRegex = [regex]("(?s)(id=`"" + $sectionId + "`".*?)(</ul>)")
        $sectionMatch = $sectionRegex.Match($updatedContent)

        if (-not $sectionMatch.Success) {
            Write-Host "  WARNING: Could not locate section '$sectionId' in index.html to insert new guide." -ForegroundColor Yellow
            continue
        }

        # Skip insertion if an entry with this exact href already exists anywhere in the section
        $sectionBlock = $updatedContent.Substring($sectionMatch.Index, $sectionMatch.Length)
        $escapedOutputFile = [regex]::Escape($OutputFile)
        if ([regex]::IsMatch($sectionBlock, "href=`"$escapedOutputFile`"")) {
            Write-Host "  Skipping insert into '$sectionId' - href already present: $OutputFile" -ForegroundColor DarkGray
            continue
        }

        # Find the category-aware insertion position
        $insertPos = Get-CategoryInsertPosition -Content $updatedContent -SectionId $sectionId -CategoryName $categoryHeader

        if ($insertPos -lt 0) {
            Write-Host "  WARNING: Category '$categoryHeader' not found in '$sectionId'. Appending to end of section." -ForegroundColor Yellow
            $insertPos = $sectionMatch.Groups[2].Index
        }

        $updatedContent = $updatedContent.Substring(0, $insertPos) + $newLi + "`r`n" + $updatedContent.Substring($insertPos)
        $anyInserted = $true
        Write-Host "  Queued insert into section: $sectionId (under '$categoryHeader')" -ForegroundColor DarkGray
    }

    if ($anyInserted) {
        if (-not $DryRun) {
            Set-Content -Path $IndexFile -Value $updatedContent -Encoding UTF8 -NoNewline
            Write-Host "  Added new entry to index.html: $GuideTitle" -ForegroundColor Green
        } else {
            Write-Host "  [DRY RUN] Would add new entry to index.html: $GuideTitle (under '$categoryHeader')" -ForegroundColor DarkYellow
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: Update the visible link text of an already-converted entry in index.html
# Targets any <a> whose href matches the outputFile and updates its inner text
# ---------------------------------------------------------------------------
function Update-IndexLinkText {
    param(
        [string]$OutputFile,
        [string]$NewTitle
    )

    $indexContent = Get-Content $IndexFile -Raw -Encoding UTF8
    $escapedTitle = $NewTitle -replace "&", "&amp;"
    $escapedPath  = [regex]::Escape($OutputFile)

    # Match the full anchor block for this outputFile (already converted, no guide-pending)
    $anchorRegex = [regex]("(?s)(<a\b[^>]*href=`"" + $escapedPath + "`"[^>]*>)([\s\S]*?)(</a>)")
    $anchorMatch = $anchorRegex.Match($indexContent)

    if (-not $anchorMatch.Success) {
        return $false   # not found - caller will decide what to do
    }

    $currentText = $anchorMatch.Groups[2].Value.Trim()
    if ($currentText -ieq $escapedTitle) {
        Write-Host "  index.html link text already matches filename title." -ForegroundColor DarkGray
        return $true
    }

    $updated = $anchorRegex.Replace($indexContent, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return $m.Groups[1].Value + "`r`n                  $escapedTitle`r`n                " + $m.Groups[3].Value
    })

    if (-not $DryRun) {
        Set-Content -Path $IndexFile -Value $updated -Encoding UTF8 -NoNewline
        Write-Host "  Updated index.html link text: '$currentText' -> '$escapedTitle'" -ForegroundColor Green
    } else {
        Write-Host "  [DRY RUN] Would update index.html link text: '$currentText' -> '$escapedTitle'" -ForegroundColor DarkYellow
    }
    return $true
}

# ---------------------------------------------------------------------------
# Helper: Move a .docx file to the matching Worked subfolder
# ---------------------------------------------------------------------------
function Move-ToWorked {
    param([string]$DocxPath, [string]$SubFolder)

    $workedSubDir = Join-Path $MarkdownWorkedDir $SubFolder
    $null = New-Item -ItemType Directory -Path $workedSubDir -Force
    $destPath = Join-Path $workedSubDir (Split-Path $DocxPath -Leaf)
    Move-Item -Path $DocxPath -Destination $destPath -Force
    Write-Host "  Moved to Worked: $SubFolder\$(Split-Path $DocxPath -Leaf)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Process a single guide from a .docx markdown file
# ---------------------------------------------------------------------------
function Convert-MarkdownGuide {
    param(
        [string]$DocxPath,
        [string]$SubFolder   # e.g. "Mobile" or "OLB"
    )

    $fileName = Split-Path $DocxPath -Leaf
    $section  = Get-SectionFromFolder $SubFolder

    Write-Host ""
    Write-Host "Converting (markdown): $fileName" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would read and parse: $DocxPath" -ForegroundColor DarkYellow
    }

    # 1. Extract text from docx
    $markdownText = Get-DocxText -DocxPath $DocxPath
    if ([string]::IsNullOrWhiteSpace($markdownText)) {
        Write-Host "  ERROR: Could not extract text from $fileName. Skipping." -ForegroundColor Red
        return
    }

    # 2. Parse markdown into guide structure
    $parsed = Parse-DocxMarkdown -markdownText $markdownText -docxFileName $fileName

    Write-Host "  Title:  $($parsed.Title)"
    Write-Host "  Parsed: $($parsed.Items.Count) steps"

    if ($parsed.Items.Count -eq 0) {
        Write-Host "  ERROR: No steps parsed from $fileName. Skipping." -ForegroundColor Red
        return
    }

    # 3. Derive output paths from title
    $outputFile = Get-OutputFileFromTitle -title $parsed.Title -section $section
    $slug       = Get-Slug $outputFile
    $imageSlug  = "$slug-$section"   # e.g. "send-money-to-a-person-mobile" — prevents collisions across sections
    $outputPath = Join-Path $RepoRoot $outputFile
    $imageDir   = Join-Path $RepoRoot "images\guides\$imageSlug"

    Write-Host "  Output: $outputFile"
    Write-Host "  Images: images/guides/$imageSlug/"

    # 4. Download images
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

    # 5. Generate HTML
    $html = Generate-GuideHtml -Parsed $parsed -Slug $imageSlug -Section $section

    # 6. Write output file
    if (-not $DryRun) {
        $null = New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force
        Set-Content -Path $outputPath -Value $html -Encoding UTF8 -NoNewline
        Write-Host "  Written: $outputFile" -ForegroundColor Green
    } else {
        Write-Host "  [DRY RUN] Would write: $outputFile ($($html.Length) chars)" -ForegroundColor DarkYellow
    }

    # 7. Update index.html
    # The authoritative title is the docx filename stem (already in $parsed.Title)
    # Match against guides-to-convert.json using the filename-derived title (case-insensitive)
    $matchedGuide = $AllGuides | Where-Object { $_.title -ieq $parsed.Title } | Select-Object -First 1

    Write-Host "  Updating index.html..." -ForegroundColor DarkGray

    if ($matchedGuide) {
        # Case A: matched a pending entry in the queue — replace it and fix link text
        Update-IndexHtml -GuideTitle $parsed.Title -OutputFile $outputFile -Keywords $matchedGuide.keywords -ScribeUrl $matchedGuide.scribeUrl

        # 8. Remove from queue
        if (-not $DryRun) {
            Remove-FromQueue -OutputFile $matchedGuide.outputFile -Section $section
        }
    } else {
        # Case B: check whether an already-converted entry exists for this outputFile
        $alreadyConverted = Update-IndexLinkText -OutputFile $outputFile -NewTitle $parsed.Title

        if (-not $alreadyConverted) {
            # Case C: no entry at all — generate keywords and insert a new <li>
            Write-Host "  No existing index.html entry found for '$($parsed.Title)'. Adding new entry." -ForegroundColor Yellow
            $autoKeywords = Generate-Keywords -title $parsed.Title -section $section
            Write-Host "  Auto-keywords: $autoKeywords" -ForegroundColor DarkGray
            if (-not $DryRun) {
                Add-ToIndexHtml -GuideTitle $parsed.Title -OutputFile $outputFile -Keywords $autoKeywords -Section $section
            } else {
                Write-Host "  [DRY RUN] Would add new entry with keywords: $autoKeywords" -ForegroundColor DarkYellow
            }
        }
    }

    # 9. Move .docx to Worked folder
    if (-not $DryRun) {
        Move-ToWorked -DocxPath $DocxPath -SubFolder $SubFolder
    } else {
        Write-Host "  [DRY RUN] Would move to: Working\Markdown\Worked\$SubFolder\$fileName" -ForegroundColor DarkYellow
    }

    Write-Host "  Done: $($parsed.Title)" -ForegroundColor Green
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
        $DecodedUrl = [System.Web.HttpUtility]::HtmlDecode($ImageUrl)
        $wc.DownloadFile($DecodedUrl, $savePath)
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

    # Separate pre-step cards (cards before the first step) from the rest
    $preStepHtml = [System.Text.StringBuilder]::new()
    $stepsHtml   = [System.Text.StringBuilder]::new()
    $seenStep    = $false

    foreach ($item in $Parsed.Items) {
        if ($item.type -eq "step") {
            $seenStep = $true
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
            # Build optional bullet list
            $listHtml = ""
            if ($item.listItems -and $item.listItems.Count -gt 0) {
                $liItems = ($item.listItems | ForEach-Object { "                    <li>$(Escape-Html $_)</li>" }) -join "`n"
                $listHtml = "`n                <ul>`n$liItems`n                </ul>"
            }
            # Cards before any step render outside .steps div; cards after a step go inside
            $target = if ($seenStep) { $stepsHtml } else { $preStepHtml }
            if ($item.cardType -eq "warning") {
                $null = $target.Append(@"

        <!-- Warning -->
        <div class="warning-card">
            <i class="bi bi-exclamation-triangle-fill card-icon"></i>
            <div class="warning-text">
                <strong>$cardText</strong>$listHtml
            </div>
        </div>
"@)
            } else {
                $null = $target.Append(@"

        <!-- Tip -->
        <div class="tip-card">
            <span class="card-icon">&#x24D8;</span>
            <div class="tip-text">
                <strong>$cardText</strong>$listHtml
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
    <link rel="icon" type="image/png" sizes="32x32" href="../../favicon-32x32.png">
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
        </div>$($preStepHtml.ToString())
        
        <div class="steps">$($stepsHtml.ToString())
        </div>
    </div>
</body>
</html>
"@
}

# ---------------------------------------------------------------------------
# Update index.html: replace a guide-pending anchor with a local link
# Called when a pending ScribeHow entry still exists in index.html for this guide
# ---------------------------------------------------------------------------
function Update-IndexHtml {
    param(
        [string]$GuideTitle,
        [string]$OutputFile,
        [string]$Keywords,
        [string]$ScribeUrl
    )

    $indexContent = Get-Content $IndexFile -Raw -Encoding UTF8
    $escapedTitle = $GuideTitle -replace "&", "&amp;"
    $escapedUrl   = [regex]::Escape($ScribeUrl.Split("?")[0])

    $q = '"'
    $anchorRegex = [regex]('(?s)(<a\s[^>]*?class=' + $q + '[^' + $q + ']*?guide-pending[^' + $q + ']*?' + $q + '[^>]*?href=' + $q + '[^' + $q + ']*?' + $escapedUrl + '[^' + $q + ']*?' + $q + '[\s\S]*?>)([\s\S]*?)(</a>)')

    $anchorMatches = $anchorRegex.Matches($indexContent)
    if ($anchorMatches.Count -eq 0) {
        Write-Host "  WARNING: Could not find pending anchor for '$GuideTitle' in index.html" -ForegroundColor Yellow
        Write-Host "           Searched for URL fragment: $($ScribeUrl.Split('?')[0])" -ForegroundColor DarkGray
        return
    }

    $updated = $anchorRegex.Replace($indexContent, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $newTag = $m.Groups[1].Value
        $newTag = [regex]::Replace($newTag, '\s*guide-pending\s*', ' ')
        $newTag = [regex]::Replace($newTag, '\s*target="_blank"\s*', ' ')
        $newTag = [regex]::Replace($newTag, '\s*rel="noopener"\s*', ' ')
        $newTag = [regex]::Replace($newTag, 'href="[^"]*"', "href=`"$OutputFile`"")
        $newTag = [regex]::Replace($newTag, 'class="([^"]*?)\s{2,}([^"]*?)"', 'class="$1 $2"')
        $newTag = $newTag.TrimEnd()
        return "$newTag`r`n                  $escapedTitle`r`n                </a>"
    })

    if ($updated -eq $indexContent) {
        Write-Host "  WARNING: Replacement made no change in index.html for '$GuideTitle'" -ForegroundColor Yellow
    } else {
        Write-Host "  Updated $($anchorMatches.Count) occurrence(s) in index.html" -ForegroundColor Green
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

    $json      = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $remaining = $json.$Section | Where-Object { $_.outputFile -ne $OutputFile }
    $json.$Section = $remaining

    if (-not $DryRun) {
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile -Encoding UTF8
        Write-Host "  Removed from guides-to-convert.json" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Helper: Remove <li> entries from index.html whose href points to a local guide
# file that does not exist on disk. guide-pending (Scribe) entries are left alone.
# Call this once after all guides have been converted.
# ---------------------------------------------------------------------------
function Remove-DeadIndexEntries {

    $indexContent = Get-Content $IndexFile -Raw -Encoding UTF8
    $changed = $false

    # Match every <li class="list-group-item">...</li> block (non-greedy)
    $liRegex = [regex]'(?s)<li class="list-group-item">.*?</li>'
    $matches  = $liRegex.Matches($indexContent)

    # Collect blocks to remove (work in reverse order to preserve indices)
    $toRemove = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()

    foreach ($m in $matches) {
        $block = $m.Value

        if ($block -match 'guide-pending') {
            # guide-pending (Scribe) entry: remove it if a local converted guide already
            # exists for this section. Extract the visible link text, slugify it, and check
            # both guides/online/ and guides/mobile/ for a matching file.
            if ($block -match '(?s)>\s*([^<]{3,}?)\s*</a>') {
                $linkText = $Matches[1].Trim()
                $slug = $linkText.ToLower() `
                    -replace '[^a-z0-9\s-]', '' `
                    -replace '\s+', '-' `
                    -replace '-{2,}', '-'
                $foundLocal = $false
                foreach ($sec in @("online", "mobile")) {
                    $candidate = Join-Path $RepoRoot "guides\$sec\$slug.html"
                    if (Test-Path $candidate) {
                        $foundLocal = $true
                        Write-Host "  Superseded Scribe entry - will remove: '$linkText' (local: guides/$sec/$slug.html)" -ForegroundColor Yellow
                        break
                    }
                }
                if ($foundLocal) { $toRemove.Add($m) }
            }
            continue
        }

        # Local guide href: remove if the file no longer exists on disk
        if ($block -notmatch 'href="(guides/[^"]+)"') { continue }

        $relPath  = $Matches[1]
        $fullPath = Join-Path $RepoRoot $relPath

        if (-not (Test-Path $fullPath)) {
            $toRemove.Add($m)
            Write-Host "  Dead link found - will remove: $relPath" -ForegroundColor Yellow
        }
    }

    if ($toRemove.Count -eq 0) {
        Write-Host "  No dead index entries found." -ForegroundColor DarkGray
        return
    }

    # Remove in reverse order so indices remain valid
    $updatedContent = $indexContent
    for ($i = $toRemove.Count - 1; $i -ge 0; $i--) {
        $m = $toRemove[$i]
        # Also consume a trailing newline/whitespace line if present
        $endIdx  = $m.Index + $m.Length
        $snippet = $updatedContent.Substring($endIdx)
        $trailingNewline = [regex]::Match($snippet, '^\r?\n')
        $removeLen = $m.Length + $(if ($trailingNewline.Success) { $trailingNewline.Length } else { 0 })
        $updatedContent = $updatedContent.Substring(0, $m.Index) + $updatedContent.Substring($m.Index + $removeLen)
        $changed = $true
    }

    if ($changed) {
        if (-not $DryRun) {
            Set-Content -Path $IndexFile -Value $updatedContent -Encoding UTF8 -NoNewline
            Write-Host "  Removed $($toRemove.Count) dead index entries from index.html." -ForegroundColor Green
        } else {
            Write-Host "  [DRY RUN] Would remove $($toRemove.Count) dead index entries from index.html." -ForegroundColor DarkYellow
        }
    }
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

$successCount = 0
$failCount    = 0

# Scan Working/Markdown/New subfolders for .docx files
$subFolders = Get-ChildItem -Path $MarkdownNewDir -Directory
$docxFiles  = @()
foreach ($sub in $subFolders) {
    $files = @(Get-ChildItem -Path $sub.FullName -Filter "*.docx" | Where-Object { $_.Name -notlike "~*" })
    foreach ($f in $files) {
        $docxFiles += [PSCustomObject]@{ Path = $f.FullName; SubFolder = $sub.Name }
    }
}

Write-Host "Guides to process: $($docxFiles.Count)"
Write-Host ""

foreach ($entry in $docxFiles) {
    try {
        Convert-MarkdownGuide -DocxPath $entry.Path -SubFolder $entry.SubFolder
        $successCount++
    } catch {
        Write-Host "  ERROR processing '$($entry.Path)': $_" -ForegroundColor Red
        $failCount++
    }
}

# After all guides processed, clean up any dead local links in the index
Write-Host ""
Write-Host "Cleaning up dead index entries..." -ForegroundColor Cyan
Remove-DeadIndexEntries

Write-Host ""
Write-Host "============================"  -ForegroundColor Cyan
Write-Host "Complete: $successCount succeeded, $failCount failed" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
if (-not $DryRun -and $successCount -gt 0) {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Open each generated guide in a browser and verify the content looks correct."
    Write-Host "  2. Check images rendered at the right steps."
    Write-Host "  3. Commit and push when satisfied."
}
