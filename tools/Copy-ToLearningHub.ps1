# Copy-ToLearningHub.ps1
# Copies all files and folders from the current repo to C:\Dev\LearningHub
# Excludes: Working folder and .gitignore file
# Only overwrites files if source is newer

param(
    [string]$SourcePath = $PSScriptRoot,
    [string]$DestinationPath = "C:\Dev\LearningHub"
)

# Get the root directory of the repo (one level up from tools folder)
$RepoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Source: $RepoRoot" -ForegroundColor Green
Write-Host "Destination: $DestinationPath" -ForegroundColor Green
Write-Host ""

# Show what will be copied
Write-Host "The following will be copied:" -ForegroundColor Yellow
Write-Host "- All files and folders from the repository"
Write-Host "- EXCEPT: Working folder and .gitignore file"
Write-Host "- Files will only be overwritten if source is newer"
Write-Host ""

# Confirmation
$confirmation = Read-Host "Do you want to continue? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Operation cancelled." -ForegroundColor Red
    exit 0
}

# Check if destination exists, create if not
if (-not (Test-Path $DestinationPath)) {
    Write-Host "Creating destination directory: $DestinationPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
}

# Get all items in the repo root
$items = Get-ChildItem -Path $RepoRoot -Force

foreach ($item in $items) {
    # Skip Working folder, tools folder, .gitignore file, and .git folder
    if (($item.Name -eq "Working" -and $item.PSIsContainer) -or 
        ($item.Name -eq "tools" -and $item.PSIsContainer) -or 
        $item.Name -eq ".gitignore" -or 
        $item.Name -eq ".git") {
        Write-Host "Skipping: $($item.Name)" -ForegroundColor Gray
        continue
    }
    
    $sourceItem = $item.FullName
    $destItem = Join-Path $DestinationPath $item.Name
    
    if ($item.PSIsContainer) {
        # It's a directory, copy recursively
        Write-Host "Copying folder: $($item.Name)" -ForegroundColor Cyan
        
        if (Test-Path $destItem) {
            # Directory exists, copy contents with newer file check
            Copy-Item -Path $sourceItem -Destination $destItem -Recurse -Force
        } else {
            # Directory doesn't exist, create it
            New-Item -ItemType Directory -Path $destItem -Force | Out-Null
            Copy-Item -Path $sourceItem -Destination $destItem -Recurse -Force
        }
    } else {
        # It's a file
        $shouldCopy = $false
        
        if (Test-Path $destItem) {
            # Destination file exists, check modification dates
            $sourceTime = (Get-Item $sourceItem).LastWriteTime
            $destTime = (Get-Item $destItem).LastWriteTime
            
            if ($sourceTime -gt $destTime) {
                $shouldCopy = $true
                Write-Host "Updating file: $($item.Name) (source is newer)" -ForegroundColor Green
            } else {
                Write-Host "Skipping file: $($item.Name) (destination is newer or same)" -ForegroundColor Gray
            }
        } else {
            # Destination file doesn't exist
            $shouldCopy = $true
            Write-Host "Copying new file: $($item.Name)" -ForegroundColor Green
        }
        
        if ($shouldCopy) {
            Copy-Item -Path $sourceItem -Destination $destItem -Force
        }
    }
}

Write-Host ""
Write-Host "Copy operation completed!" -ForegroundColor Green
