# DEFINE PATHS
$repoA = "C:\Users\jad.abouibrahim\Desktop\webui\custom" #Remote
$repoB = "C:\Users\jad.abouibrahim\Desktop\custom"           #Local

#DEFINE THE MERGING TOOL YOU ARE USING FOR THE COMPARISON 
$tool = '"C:\Program Files\TortoiseGit\bin\TortoiseGitMerge.exe"'

#DEFINE IF WE WANT AUTOMOVE  
$ISMOVE = 1

#DEFINE HOUR OFFSET TO NORMALIZE BETWEEN DIFFERENT TIMEZONES 
$offset = -0 

# Get all files recursively
$filesA = Get-ChildItem -Path $repoA -Recurse | Where-Object { -not $_.PSIsContainer }
$filesB = Get-ChildItem -Path $repoB -Recurse | Where-Object { -not $_.PSIsContainer }

# Create relative path lookup
$mapA = @{}
foreach ($file in $filesA) {cls
    $relative = $file.FullName.Replace($repoA, "")
    $mapA[$relative] = $file
}

$mapB = @{}
foreach ($file in $filesB) {
    $relative = $file.FullName.Replace($repoB, "")
    $mapB[$relative] = $file
}

# Collections to store results
$differentDates = @()
$onlyInA = @()
$onlyInB = @()

# Compare
foreach ($relative in $mapA.Keys) {
    if ($mapB.ContainsKey($relative)) {
        if ($mapA[$relative].LastWriteTimeUtc.AddHours($offset) -ne $mapB[$relative].LastWriteTimeUtc) {
            $differentDates += [PSCustomObject]@{
                File        = $relative
                RepoA_Date  = $mapA[$relative].LastWriteTimeUtc.AddHours($offset)
                RepoB_Date  = $mapB[$relative].LastWriteTimeUtc
            }
        }
    } else {
        $onlyInA += $relative
    }
}

foreach ($relative in $mapB.Keys) {
    if (-not $mapA.ContainsKey($relative)) {
        $onlyInB += $relative
    }
}

# Sort
$differentDates = $differentDates | Sort-Object File
$onlyInA = $onlyInA | Sort-Object
$onlyInB = $onlyInB | Sort-Object

# --- OUTPUT ---
Write-Host "`n===== Files with DIFFERENT Last-Modified Dates =====" -ForegroundColor Yellow
$differentDates | Format-Table

Write-Host "`n===== Files ONLY in Repo A (Remote) =====" -ForegroundColor Green
$onlyInA | ForEach-Object { Write-Host $_ }

Write-Host "`n===== Files ONLY in Repo B (Local) =====" -ForegroundColor Magenta
$onlyInB | ForEach-Object { Write-Host $_ }


if ($ISMOVE -eq 1) {
Write-Host "`n===== Copying files missing in Repo A =====" -ForegroundColor Cyan

foreach ($relative in $onlyInA) {

    # Full source file path (in repo A)
    $source = Join-Path $repoA $relative

    # Full destination file path (in repo B)
    $destination = Join-Path $repoB $relative

    # Ensure the target directory exists
    $destDir = Split-Path $destination
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Copy file (only if it does NOT already exist)
    if (-not (Test-Path $destination)) {
        Copy-Item -Path $source -Destination $destination -Force
        Write-Host "Copied: $relative"
    }
    else {
        Write-Host "Skipped (already exists): $relative" -ForegroundColor Yellow
    }
}

Write-Host "`nCompleted copying missing files from Repo A → Repo B." -ForegroundColor Green
}
else {
Write-Host "`nDid not automove the files." -ForegroundColor Yellow
}

# --- GENERATE TORTOISEGITMERGE COMMANDS ---
Write-Host "`n===== TortoiseGitMerge Commands =====" -ForegroundColor Cyan

foreach ($item in $differentDates) {
    
    # Full paths for each file
    $filePathA = Join-Path $repoA $item.File
    $filePathB = Join-Path $repoB $item.File

    # Final command
    $cmd = "$tool /base:`"$filePathA`" /mine:`"$filePathB`""

    Write-Host $cmd
}
