# Process: Updating Guide Screenshots with Baked-In Scribehow Highlights

This documents the exact steps used to replace guide screenshots with versions that have
Scribehow's green click-target circles baked into the image, eliminating the need for
custom CSS overlay highlights.

---

## Prerequisites

- The guide must have a **Scribehow markdown export** (`.docx` file) in `Working\Markdown\`.
  Scribehow's markdown/docx export embeds image URLs that end with `_text_export.jpeg` —
  these are the versions with **baked-in green circle highlights**.
- The images downloaded by `convert-guide.ps1` (from the rendered Scribehow DOM) do **NOT**
  have baked-in highlights — they use a different URL pattern through `cloudimg.io`.

## Step-by-Step Process

### 1. Extract image URLs from the `.docx` file

The `.docx` is a ZIP archive. Extract the `word/document.xml` entry and pull out image URLs:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("C:\Dev\LearningHub-private\Working\Markdown\<Guide Name>.docx")
$entry = $zip.Entries | Where-Object { $_.FullName -eq "word/document.xml" }
$stream = $entry.Open()
$reader = New-Object System.IO.StreamReader($stream)
$content = $reader.ReadToEnd()
$reader.Close(); $stream.Close(); $zip.Dispose()

# Strip XML tags and extract plain text with URLs
$plain = $content -replace '<[^>]+>', ' ' -replace '\s+', ' '

# Extract all colony-recorder S3 image URLs
[regex]::Matches($plain, 'https://colony-recorder\.s3\.amazonaws\.com/[^\s\)]+') |
  ForEach-Object { $_.Value }
```

**Key insight:** The URLs ending in `_text_export.jpeg` are the ones with baked-in highlights.
These differ from the `cloudimg.io` URLs used by the Scribehow viewer DOM.

### 2. Download the images

```powershell
$urls = @(
  "https://colony-recorder.s3.amazonaws.com/files/YYYY-MM-DD/<guid>/..._text_export.jpeg",
  # ... one URL per step
)
$outDir = "C:\Dev\LearningHub-private\images\guides\<guide-slug>"
for ($i = 0; $i -lt $urls.Count; $i++) {
  $num = "{0:D2}" -f ($i + 1)
  $outFile = Join-Path $outDir "step-$num.jpeg"
  Invoke-WebRequest -Uri $urls[$i] -OutFile $outFile -ErrorAction Stop
  Write-Output "Downloaded step-$num"
}
```

### 3. Verify baked-in highlights

Open each downloaded image and visually confirm the green circle highlights are present.
Not all steps will have highlights (e.g., informational screenshots or steps showing
DELETE/EDIT buttons where the action is self-evident).

### 4. Update the HTML guide file

For each step in the guide HTML (`guides/mobile/<guide-slug>.html`):

**a) Change image file extension** from `.webp` to `.jpeg`:
```
BEFORE: src="../../images/guides/<slug>/step-01.webp"
AFTER:  src="../../images/guides/<slug>/step-01.jpeg"
```

**b) Remove the CSS overlay structure** — replace the `image-highlight-wrapper` + `click-target`
with a plain `<img>`:

```html
<!-- BEFORE (with CSS overlay): -->
<div class="image-container">
    <div class="image-highlight-wrapper">
        <img src="../../images/guides/<slug>/step-01.webp" alt="...">
        <div class="click-target" style="top: 94%; left: 50%;"></div>
    </div>
</div>

<!-- AFTER (baked-in highlights, no CSS overlay): -->
<div class="image-container">
    <img src="../../images/guides/<slug>/step-01.jpeg" alt="...">
</div>
```

### 5. Update the description (optional)

If the markdown source has a different/better description than the current HTML, update
the `<p class="description">` text to match.

---

## Guides Updated Using This Process

| Guide | Markdown Source | Steps | Images with Baked-In Highlights |
|-------|----------------|-------|---------------------------------|
| edit-scheduled-external-transfers | `Edit scheduled external transfer.docx` | 4 | Steps 1-3 (step 4 shows DELETE/EDIT buttons) |
| edit-scheduled-person-payments | `Edit scheduled person payment.docx` | 4 | Steps 1-3 (step 4 shows DELETE/EDIT buttons) |
| add-external-account | `Add an external account for transfers.docx` | 17 | All steps have baked-in highlights |
| making-a-mobile-deposit | `Making a mobile deposit.docx` | 5 | All steps have baked-in highlights |
| open-a-new-account | `Open a new account.docx` | 9 | Step 1 only (steps 2-9 still use CSS overlays) |

## Guides NOT Updated (No Markdown Export Available)

| Guide | Reason | Current State |
|-------|--------|---------------|
| edit-scheduled-bill-payments | No `.docx` file in Markdown folder | Still uses `.webp` images + CSS overlays |

**To update bill payments:** Export the guide from Scribehow as markdown/docx, save it to
`Working\Markdown\`, then follow the process above.

---

## Important Notes

- The `_text_export.jpeg` URL pattern is specific to Scribehow's **markdown/docx export**.
  The Scribehow viewer page uses a different URL pattern (`cloudimg.io`) that does NOT
  include baked-in highlights.
- Images are saved as `.jpeg` (not `.webp`) because Scribehow's text export only provides JPEG.
- The CSS classes `.image-highlight-wrapper` and `.click-target` in `guide.css` remain available
  for guides where baked-in highlights are not present and CSS overlays are still needed.
