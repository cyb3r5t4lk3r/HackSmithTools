<#
.SYNOPSIS
Extracts files from a .git directory and saves them into a specified output directory with the same folder structure. Optionally, analyzes files for sensitive data.

.DESCRIPTION
This script installs Git using winget if it is not already installed, and then extracts files from a specified .git directory.
It saves the files into an output directory, maintaining the same folder structure as the original repository.
Optionally, it can log the extraction process to the console or analyze files in the output directory for sensitive data.

.PARAMETER GitDirectory
The path to the .git directory that contains the repository data. Can be a relative or absolute path.

.PARAMETER OutputDirectory
The path to the directory where the extracted files will be saved. Can be a directory name or a full path.

.PARAMETER Logging
A switch parameter to enable logging of the extraction process.

.PARAMETER AnalyseFiles
A switch parameter to enable analysis of files in the output directory for sensitive data.

.PARAMETER SensitiveStringsFile
The path to the file containing strings to search for during analysis.

.PARAMETER AnalyseOutput
The output format for the analysis results. Can be 'CSV', 'Console', or 'GridView'.

.EXAMPLE
.\Extract-DataFromGitOfflineFolder.ps1 -GitDirectory ".\path\to\.git" -OutputDirectory "output_directory" -Logging -AnalyseFiles -SensitiveStringsFile ".\sensitive_strings.txt" -AnalyseOutput CSV

#>

param (
    [string]$GitDirectory,
    [string]$OutputDirectory,
    [switch]$Logging,
    [switch]$AnalyseFiles,
    [string]$SensitiveStringsFile,
    [ValidateSet("CSV", "Console", "GridView")][string]$AnalyseOutput
)

function Install-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Git is already installed." -ForegroundColor Yellow
    } else {
        Write-Host "Installing Git..." -ForegroundColor Yellow
        winget install git
    }
}

function Extract-Git-Files {
    param (
        [string]$GitDirectory,
        [string]$OutputDirectory,
        [switch]$Logging
    )

    # Resolve the GitDirectory path
    $GitDirectory = Resolve-Path $GitDirectory

    # Resolve the OutputDirectory path
    if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory = Resolve-Path $OutputDirectory
    } else {
        $OutputDirectory = Join-Path -Path (Get-Location) -ChildPath $OutputDirectory
    }

    if (-not (Test-Path $GitDirectory)) {
        throw "The directory '$($GitDirectory)' does not exist."
    }

    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    Set-Location $GitDirectory

    # Get SHA1 from master branch
    $MasterID = Get-Content .\refs\heads\master

    function Get-Tree-Blobs {
        param (
            [string]$TreeSHA,
            [string]$CurrentPath
        )

        $GitTree = git cat-file -p $TreeSHA
        $Blobs = ($GitTree | Select-String -Pattern blob).Line
        $Trees = ($GitTree | Select-String -Pattern tree).Line

        # Process blobs
        foreach ($Blob in $Blobs) {
            $BlobSHA = ($Blob.Split(" ")[-1]).Split("`t")[0]
            $BlobPath = ($Blob.Split(" ")[-1]).Split("`t")[1]
            $OutputFilePath = Join-Path -Path $OutputDirectory -ChildPath (Join-Path -Path $CurrentPath -ChildPath $BlobPath)
            $OutputFileDir = Split-Path -Path $OutputFilePath -Parent

            if (-not (Test-Path $OutputFileDir)) {
                New-Item -ItemType Directory -Path $OutputFileDir | Out-Null
            }

            git show -p $BlobSHA | Out-File -FilePath $OutputFilePath -Encoding utf8

            if ($Logging) {
                Write-Host "File '$($OutputFilePath)' has been created." -ForegroundColor Green
            }
        }

        # Process trees (directories)
        foreach ($Tree in $Trees) {
            $TreeSHA = ($Tree.Split(" ")[-1]).Split("`t")[0]
            $TreePath = ($Tree.Split(" ")[-1]).Split("`t")[1]
            Get-Tree-Blobs -TreeSHA $TreeSHA -CurrentPath (Join-Path -Path $CurrentPath -ChildPath $TreePath)
        }
    }

    # Get root tree
    $IdentificationFromMasterID = (((git cat-file -p $MasterID) | Select-String -Pattern "tree").Line).Split(" ")[-1]
    Get-Tree-Blobs -TreeSHA $IdentificationFromMasterID -CurrentPath "."

    Write-Host "File extraction completed." -ForegroundColor Green
}

function Analyse-Files {
    param (
        [string]$Directory,
        [string]$SensitiveStringsFile,
        [string]$AnalyseOutput,
        [switch]$Logging
    )

    if (-not (Test-Path $Directory)) {
        throw "The directory '$($Directory)' does not exist."
    }

    if (-not (Test-Path $SensitiveStringsFile)) {
        throw "The sensitive strings file '$($SensitiveStringsFile)' does not exist."
    }

    $SensitiveStrings = Get-Content $SensitiveStringsFile

    $Files = Get-ChildItem -Path $Directory -Recurse -File

    if ($Files.Count -eq 0) {
        throw "The directory '$($Directory)' is empty. Nothing to analyze."
    }

    $Results = @()

    foreach ($File in $Files) {
        $Content = Get-Content $File.FullName

        foreach ($String in $SensitiveStrings) {
            $Matches = Select-String -Pattern $String -InputObject $Content

            foreach ($Match in $Matches) {
                $Results += [PSCustomObject]@{
                    FileName    = $File.Name
                    SearchString = $String
                    FilePath    = $File.FullName
                    Line        = $Match.Line
                }
            }
        }
    }

    if ($Results.Count -eq 0) {
        Write-Host "No sensitive strings found." -ForegroundColor Red
    } else {
        switch ($AnalyseOutput) {
            "CSV" {
                $CsvOutputFile = "$Directory\analysis_results.csv"
                $Results | Export-Csv -Path $CsvOutputFile -NoTypeInformation
                Write-Host "Results have been saved to '$($CsvOutputFile)'."
            }
            "Console" {
                $Results | Format-Table -AutoSize
            }
            "GridView" {
                $Results | Out-GridView -Title "Sensitive Data Analysis Results"
            }
        }
    }

    Write-Host "File analysis completed." -ForegroundColor Green
}

# Install Git
Install-Git

# Check if analysis is requested
if ($AnalyseFiles) {
    if (Test-Path $OutputDirectory) {
        $Files = Get-ChildItem -Path $OutputDirectory -Recurse -File

        if ($Files.Count -gt 0) {
            Write-Host "Output directory is not empty. Skipping extraction and starting analysis." -ForegroundColor Yellow
            Analyse-Files -Directory $OutputDirectory -SensitiveStringsFile $SensitiveStringsFile -AnalyseOutput $AnalyseOutput -Logging:$Logging
            exit
        }
    }
}

# Extract files from .git directory
Extract-Git-Files -GitDirectory $GitDirectory -OutputDirectory $OutputDirectory -Logging:$Logging

# Perform analysis if requested
if ($AnalyseFiles) {
    Analyse-Files -Directory $OutputDirectory -SensitiveStringsFile $SensitiveStringsFile -AnalyseOutput $AnalyseOutput -Logging:$Logging
}
