$EdgeExe = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path $EdgeExe)) { $EdgeExe = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = $EdgeExe
$pinfo.Arguments = '--headless --disable-gpu --dump-dom "https://scribehow.com/viewer/How_to_delete_saved_Billers_on_the_Mobile_App__j6DgH0HtRhetrv_mrHsn2A"'
# Change URL above to test other guides
$pinfo.RedirectStandardOutput = $true
$pinfo.RedirectStandardError = $true
$pinfo.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($pinfo)
$dom = $proc.StandardOutput.ReadToEnd()
$null = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

Add-Type -AssemblyName System.Web
Write-Host "DOM length: $($dom.Length)"

function Strip-Html {
    param([string]$html)
    return [System.Text.RegularExpressions.Regex]::Replace($html, '<[^>]+>', '') `
        -replace '&amp;',  '&' `
        -replace '&lt;',   '<' `
        -replace '&gt;',   '>' `
        -replace '&nbsp;', ' ' `
        -replace '&quot;', '"' `
        -replace "&#39;",  "'" `
        -replace '\s{2,}', ' '
}

$allMatches = [regex]::Matches($dom, '(?s)(<[^>]*data-testid="(action-instruction|action-tip-or-warning)"[^>]*>)([\s\S]{0,3000}?)(?=<[^>]*data-testid="(?:action-instruction|action-tip-or-warning)"|</main>|</article>|<footer)')
Write-Host "Found $($allMatches.Count) action blocks"

$stepNum = 0
foreach ($m in $allMatches) {
    $testId = $m.Groups[2].Value
    $content = $m.Groups[3].Value
    
    if ($testId -eq 'action-instruction') {
        $stepNum++
        $textMatch = [regex]::Match($content, '(?s)<div\b[^>]*class="[^"]*text-slate-900[^"]*"[^>]*>([\s\S]*?)</div>')
        if (-not $textMatch.Success) {
            $textMatch = [regex]::Match($content, '(?s)<p\b[^>]*>([\s\S]*?)</p>')
        }
        $rawText = if ($textMatch.Success) { $textMatch.Groups[1].Value } else { '(no match)' }
        $rawText = $rawText -replace '\*\*([^*]+)\*\*', '$1'
        $cleanText = ([System.Web.HttpUtility]::HtmlDecode((Strip-Html $rawText))).Trim()
        Write-Host "Step $stepNum`: $cleanText"
    } else {
        Write-Host "[CARD]: $(([System.Web.HttpUtility]::HtmlDecode((Strip-Html $content))).Trim().Substring(0,100))"
    }
}
