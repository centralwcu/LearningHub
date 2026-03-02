# Reset-AndInitialCommit.ps1
# Performs Git operations from C:\Dev\LearningHub:
# 1. Undo the last commit
# 2. Add all files
# 3. Commit with "Initial commit" message
# 4. Optionally force push to origin main

param(
    [string]$RepoPath = "C:\Dev\LearningHub"
)

# Change to the repository directory
Set-Location $RepoPath

Write-Host "Working in repository: $RepoPath" -ForegroundColor Green
Write-Host ""

# Check if we're in a git repository
if (-not (Test-Path ".git")) {
    Write-Host "Error: Not a Git repository. Make sure C:\Dev\LearningHub is a Git repo." -ForegroundColor Red
    exit 1
}

# Show current status
Write-Host "Current Git status:" -ForegroundColor Yellow
git status
Write-Host ""

# Show recent commits
Write-Host "Recent commits:" -ForegroundColor Yellow
git log --oneline -5
Write-Host ""

# Step 1: Undo the last commit but keep changes
Write-Host "Step 1: Undoing the last commit but keeping changes..." -ForegroundColor Cyan

# Check if there are commits to undo
$commitCount = git rev-list --count HEAD 2>$null

if ($LASTEXITCODE -eq 0 -and [int]$commitCount -gt 0) {
    if ([int]$commitCount -eq 1) {
        Write-Host "Only one commit found. Removing it and keeping changes..." -ForegroundColor Yellow
        # For single commit, we need to delete the branch and recreate it
        # First, get the current branch name
        $currentBranch = git rev-parse --abbrev-ref HEAD
        
        # Update the ref to remove the commit but keep the index and working tree
        git update-ref -d HEAD
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to remove commit." -ForegroundColor Red
            exit 1
        }
        Write-Host "Commit removed successfully, changes preserved." -ForegroundColor Green
    } else {
        git reset --soft HEAD~1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to reset last commit." -ForegroundColor Red
            exit 1
        }
        Write-Host "Last commit undone successfully, changes preserved." -ForegroundColor Green
    }
} else {
    Write-Host "No commits found. Proceeding to add files..." -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Add all files
Write-Host "Step 2: Adding all files..." -ForegroundColor Cyan
git add .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to add files." -ForegroundColor Red
    exit 1
}

Write-Host "All files added successfully." -ForegroundColor Green
Write-Host ""

# Step 3: Commit with "Initial commit" message
Write-Host "Step 3: Creating initial commit..." -ForegroundColor Cyan
git commit -m "Initial commit"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create commit. There might be no changes to commit." -ForegroundColor Red
    exit 1
}

Write-Host "Initial commit created successfully." -ForegroundColor Green
Write-Host ""

# Show new commit
Write-Host "New commit created:" -ForegroundColor Yellow
git log --oneline -1
Write-Host ""

# Step 4: Prompt for force push
Write-Host "Step 4: Push to remote repository" -ForegroundColor Yellow
$pushConfirmation = Read-Host "Do you want to force push to origin main? This will overwrite the remote history. (y/N)"

if ($pushConfirmation -eq 'y' -or $pushConfirmation -eq 'Y') {
    Write-Host "Force pushing to origin main..." -ForegroundColor Cyan
    git push origin main --force
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to push to remote. Check your remote configuration and authentication." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Force push completed successfully." -ForegroundColor Green
} else {
    Write-Host "Force push skipped. You can push manually later with: git push origin main --force" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Git operations completed!" -ForegroundColor Green
