# Learning Hub - Private Development Repository

This is a private repository for developing and testing Learning Hub changes before deploying them to the public repository. It contains tools for converting guides from Scribehow, managing content, and deploying changes to the public repository.

## Repository Structure

```
LearningHub-private/
├── tools/                          # PowerShell scripts for automation
│   ├── convert-guide.ps1          # Convert markdown guides to HTML
│   ├── Copy-ToLearningHub.ps1     # Deploy changes to public repo
│   └── Reset-AndInitialCommit.ps1 # Reset public repo to single commit
├── Working/                       # Development workspace
│   ├── Markdown/                  # Guide content from Scribehow
│   │   ├── New/                   # New guides to be processed
│   │   └── Worked/                # Processed guides
│   └── images/                    # Local images for guides
├── guides/                        # Generated HTML guides
│   ├── mobile/                    # Mobile banking guides
│   └── online/                    # Online banking guides
├── css/                           # Stylesheets
├── js/                            # JavaScript files
├── images/                        # Static images
└── index.html                     # Main hub page
```

## Workflow Overview

### 1. Guide Creation Process
1. **Create guides in Scribehow** - Use Scribehow to create step-by-step guides
2. **Export as markdown** - Export guides as markdown files
3. **Place in Working/Markdown/New/** - Organize guides by section:
   - `Mobile/` subfolder → mobile guides
   - `OLB/` subfolder → online guides
4. **Run convert-guide.ps1** - Automatically converts markdown to HTML and places them in the appropriate guide directories

### 2. Testing and Development
- Test HTML changes locally in this private repository
- Use the `Working/` directory for development files and testing
- Validate guide functionality before deployment

### 3. Deployment to Public Repository
1. **Run Copy-ToLearningHub.ps1** - Copies all changes (except Working/ and tools/) to the public repository
2. **Run Reset-AndInitialCommit.ps1** - Resets the public repository to maintain a single "Initial commit"
3. **Push to production** - Deploy changes to the live Learning Hub

## Key Scripts

### convert-guide.ps1
Converts markdown guides from `Working/Markdown/New/` to HTML format and places them in the appropriate guide directories.

**Features:**
- Automatically detects guide type (mobile/online) based on folder structure
- Downloads and localizes images from Scribehow
- Generates HTML using the established guide template
- Updates `index.html` with new guide links
- Moves processed files to `Working/Markdown/Worked/`

**Usage:**
```powershell
# Normal operation
.\tools\convert-guide.ps1

# Dry run to see what would be generated
.\tools\convert-guide.ps1 -DryRun
```

### Copy-ToLearningHub.ps1
Copies all repository files to the public Learning Hub repository, excluding development-specific folders.

**Features:**
- Only overwrites files if source is newer
- Excludes `Working/`, `tools/`, `.gitignore`, and `.git/` folders
- Preserves directory structure
- Provides detailed output of operations

**Usage:**
```powershell
.\tools\Copy-ToLearningHub.ps1
```

### Reset-AndInitialCommit.ps1
Maintains the public repository as a single-commit repository for clean deployment.

**Features:**
- Undoes the last commit while preserving changes
- Adds all files and creates a new "Initial commit"
- Optionally force pushes to origin main
- Maintains clean git history for production

**Usage:**
```powershell
.\tools\Reset-AndInitialCommit.ps1
```

## Guide Configuration

Guide metadata and section assignments are managed through `Working/guides-to-convert.json`. This file contains:
- Guide titles and keywords
- Section assignments (mobile/online)
- Matching criteria for automatic processing

## Development Guidelines

### File Organization
- Keep all development work in the `Working/` directory
- Use `Working/Markdown/New/` for new guide content
- Processed guides are automatically moved to `Working/Markdown/Worked/`

### HTML Structure
All generated guides follow the established template structure:
- Bootstrap Icons CDN for icons
- Consistent CSS classes for styling
- Mobile-responsive design
- Standardized card components for tips and warnings

### CSS Guidelines
Key design decisions in `guide.css`:
- Screenshot containers use ring shadows instead of borders
- Mobile-specific optimizations (hidden logo, reduced padding)
- Consistent color schemes for card components
- Bootstrap Icons integration

## Deployment Process

1. **Development**: Make changes in this private repository
2. **Testing**: Validate changes locally
3. **Guide Conversion**: Run `convert-guide.ps1` for new guides
4. **Copy Changes**: Run `Copy-ToLearningHub.ps1` to sync to public repo
5. **Reset Git**: Run `Reset-AndInitialCommit.ps1` to clean history
6. **Deploy**: Push changes to production

## Important Notes

- This repository is **private** and used for development/testing only
- The public repository maintains a single commit for clean deployment
- Always test changes thoroughly before deploying to production
- The `Working/` directory is excluded from deployment to keep the public repo clean
- Images are automatically downloaded and localized during guide conversion

## Requirements

- PowerShell 5.1 or later
- Git for Windows
- Access to Scribehow for guide creation
- Write permissions to both private and public Learning Hub repositories
