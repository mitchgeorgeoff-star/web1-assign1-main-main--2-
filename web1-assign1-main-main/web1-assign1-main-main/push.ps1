Param(
    [string]$RemoteUrl = "",
    [string]$Branch = "main",
    [string]$Message = "Auto: commit project files",
    [switch]$ForceRemote,
    [switch]$CreateGhPages,
    [switch]$PullBeforePush,
    [switch]$ShowLog,
    [int]$NumLog = 20,
    [switch]$Force,
    [switch]$EnablePages,
    [string]$GitHubToken = ""
)

function Abort([string]$msg){ Write-Error $msg; exit 1 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Abort 'git is not installed or not on PATH. Install git and re-run this script.' }

$RepoPath = (Get-Location).Path
Write-Output "Working directory: $RepoPath"

# Initialize repo if necessary
if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    Write-Output "No .git found — initializing repository"
    git init || Abort 'git init failed'
}

# Ensure there are changes to commit
$porcelain = git status --porcelain
if ([string]::IsNullOrWhiteSpace($porcelain)) {
    Write-Output 'No changes to commit.'
} else {
    Write-Output 'Staging changes...'
    git add . || Abort 'git add failed'
    Write-Output "Committing with message: $Message"
    git commit -m "${Message}" || Abort 'git commit failed'
}

# Ensure branch
$current = git rev-parse --abbrev-ref HEAD 2>$null
if ($current -ne $Branch) {
    Write-Output "Setting branch to $Branch"
    git branch -M $Branch || Abort 'branch rename failed'
}

# Configure remote if provided
if ($RemoteUrl -ne "") {
    $existing = git remote get-url origin 2>$null
    if ($existing -and -not ($ForceRemote -or $Force)) {
        Write-Output "Remote 'origin' already set to: $existing" 
        Write-Output "Use -ForceRemote to overwrite the remote URL if you intend to change it."
    } else {
        if ($existing -and $ForceRemote) {
            Write-Output "Overwriting remote 'origin' with $RemoteUrl"
            git remote set-url origin $RemoteUrl || Abort 'set-url failed'
        } else {
            Write-Output "Adding remote 'origin' -> $RemoteUrl"
            git remote add origin $RemoteUrl || Abort 'remote add failed'
        }
    }
}

# Optional pull before push
if ($PullBeforePush) {
    if (git remote get-url origin 2>$null) {
        Write-Output "Pulling latest from origin/$Branch"
        git pull origin $Branch || Abort 'git pull failed'
    } else {
        Write-Output "No remote configured; cannot pull."
    }
}

# Optional pull before push
if ($PullBeforePush) {
    if (git remote get-url origin 2>$null) {
        Write-Output "Pulling latest from origin/$Branch"
        git pull origin $Branch || Abort 'git pull failed'
    } else {
        Write-Output "No remote configured; cannot pull."
    }
}

# Push
if ($RemoteUrl -ne "" -or (git remote get-url origin 2>$null)) {
    Write-Output "Pushing to origin/$Branch"
    $pushCmd = 'git push -u origin ' + $Branch
    if ($Force) { $pushCmd += ' --force' }
    iex $pushCmd || Abort 'git push failed'
} else {
    Write-Output "No remote configured. Skipping push. Provide -RemoteUrl to add one."
}

# Show git log if requested
if ($ShowLog) {
    Write-Output "Showing last $NumLog commits (oneline):"
    git --no-pager log --oneline -n $NumLog || Write-Output 'git log failed'
}

# Optionally enable GitHub Pages using the provided token
if ($EnablePages) {
    $effectiveRemote = $RemoteUrl
    if ([string]::IsNullOrWhiteSpace($effectiveRemote)) { $effectiveRemote = git remote get-url origin 2>$null }
    if (-not $effectiveRemote) { Write-Output 'No remote URL available to enable Pages.' }
    elseif ([string]::IsNullOrWhiteSpace($GitHubToken)) { Write-Output 'No GitHub token provided. Provide -GitHubToken to enable Pages.' }
    else {
        if ($effectiveRemote -match 'github.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(?:\.git)?$') {
            $owner = $matches['owner']
            $repo = $matches['repo']
            Write-Output "Enabling GitHub Pages for $owner/$repo using branch $Branch"
            $headers = @{ Authorization = "token $GitHubToken"; Accept = 'application/vnd.github.v3+json' }
            $body = @{ source = @{ branch = $Branch; path = '/' } } | ConvertTo-Json
            try {
                $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/pages" -Method PUT -Headers $headers -Body $body -ErrorAction Stop
                Write-Output 'GitHub Pages enabled (API responded).' 
            } catch {
                Write-Output "Failed to enable Pages: $($_.Exception.Message)"
            }
        } else {
            Write-Output "Remote URL not recognized as GitHub: $effectiveRemote"
        }
    }
}

# Show git log if requested
if ($ShowLog) {
    Write-Output "Showing last $NumLog commits (oneline):"
    git --no-pager log --oneline -n $NumLog || Write-Output 'git log failed'
}

# Optional: create and push gh-pages
if ($CreateGhPages) {
    Write-Output "Creating and pushing gh-pages branch"
    git checkout -b gh-pages || Abort 'checkout gh-pages failed'
    git push -u origin gh-pages || Abort 'push gh-pages failed'
    git checkout $Branch || Abort "failed to switch back to $Branch"
}

Write-Output 'Done.'
