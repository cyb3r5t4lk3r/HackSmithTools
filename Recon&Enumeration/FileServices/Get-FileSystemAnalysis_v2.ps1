<#
.SYNOPSIS
    This script analyzes the file system in a specified directory with enhanced debugging for memory and data handling issues.

.DESCRIPTION
    This script scans a given directory, collects file attributes, and writes them to a JSON file. It includes extra
    debugging to track variable content and memory usage to identify potential causes of duplicated data writing.

.PARAMETER FolderPath
    The path to the directory to be analyzed.

.PARAMETER JsonFilePath
    The path where the JSON output file will be saved.

.PARAMETER ErrorLogFilePath
    The path where the log of inaccessible files will be saved.

.PARAMETER BlockSize
    The number of files to process in each block before writing to the JSON file and clearing memory.

.PARAMETER VerboseLog
    Switch to enable verbose logging for detailed process information.

.PARAMETER DebugLog
    Switch to enable debug logging for troubleshooting.

.PARAMETER MemDebug
    Switch to enable memory debugging that shows detailed information about variables and memory usage.

.PARAMETER PerfMon
    Switch to enable performance monitoring during execution.

.EXAMPLE
    .\Get-FileSystemAnalysis_debug.ps1 -FolderPath "C:\Your\Folder\Path" -JsonFilePath "C:\Your\Output\File.json" -ErrorLogFilePath "C:\Your\Output\InaccessibleFiles.txt" -BlockSize 100 -MemDebug -PerfMon

.NOTES
    Autor: Daniel Hejda
    Company: Cyber Rangers s.r.o.
    Datum: 08.04.2025
#>

param (
    [string]$FolderPath = "C:\Your\Folder\Path",
    [string]$JsonFilePath = "C:\Your\Output\File.json",
    [string]$ErrorLogFilePath = "C:\Your\Output\InaccessibleFiles.txt",
    [int]$BlockSize = 100,
    [switch]$VerboseLog,
    [switch]$DebugLog,
    [switch]$MemDebug,
    [switch]$PerfMon
)

# Import the necessary module for JSON conversion
Import-Module -Name Microsoft.PowerShell.Utility

# Check if WriteAscii module is installed, if not install it
if (-not (Get-Module -ListAvailable -Name WriteAscii)) {
    Install-Module WriteAscii -Force
}

# ASCII header
Write-Ascii -InputObject 'NTFS File' -Fore rainbow -Back Black
Write-Ascii -InputObject 'System Analyser' -Fore rainbow -Back Black
if ($MemDebug) {
    Write-Ascii -InputObject 'DEBUG VERSION' -Fore red -Back Black
}

# Print parameter details
Write-Host ""
Write-Host "------------------------------------------------------------------------" -ForegroundColor Green
Write-Host -ForegroundColor Cyan "Processing the following parameters:"
Write-Host -ForegroundColor Green "[->] Folder Path: $FolderPath"
Write-Host -ForegroundColor Green "[->] JSON File Path: $JsonFilePath"
Write-Host -ForegroundColor Green "[->] Error Log File Path: $ErrorLogFilePath"
Write-Host -ForegroundColor Green "[->] Block Size: $BlockSize"
if ($MemDebug) {
    Write-Host -ForegroundColor Green "[->] Memory Debugging: Enabled"
}
if ($PerfMon) {
    Write-Host -ForegroundColor Green "[->] Performance Monitoring: Enabled"
}
Write-Host "------------------------------------------------------------------------" -ForegroundColor Green
Write-Host ""

# Start the stopwatch
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Initialize variables for tracking time between blocks
$lastBlockTime = [System.Diagnostics.Stopwatch]::StartNew()

# Získání aktuálního procesu, pokud je zapnutý monitoring výkonu
if ($PerfMon) {
    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
}

# Funkce pro získání systémových metrik
function Get-SystemMetrics {
    if (-not $PerfMon) {
        return $null
    }
    
    $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
    $cpuUsage = if ($cpuCounter) { [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 2) } else { "N/A" }
    
    $currentProcess.Refresh()
    $processMemoryMB = [math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
    
    $memoryCounter = Get-Counter '\Memory\% Committed Bytes In Use' -ErrorAction SilentlyContinue
    $memoryUsage = if ($memoryCounter) { [math]::Round($memoryCounter.CounterSamples[0].CookedValue, 2) } else { "N/A" }
    
    $diskCounter = Get-Counter '\PhysicalDisk(_Total)\Disk Bytes/sec' -ErrorAction SilentlyContinue
    $diskActivity = if ($diskCounter) { [math]::Round($diskCounter.CounterSamples[0].CookedValue / 1KB, 2) } else { "N/A" }
    
    # Zjištění aktuální velikosti výstupního souboru
    $fileSize = if (Test-Path -Path $JsonFilePath) { 
        $fileSizeBytes = (Get-Item -Path $JsonFilePath).Length
        if ($fileSizeBytes -gt 1GB) {
            [math]::Round($fileSizeBytes / 1GB, 2).ToString() + " GB"
        } elseif ($fileSizeBytes -gt 1MB) {
            [math]::Round($fileSizeBytes / 1MB, 2).ToString() + " MB"
        } else {
            [math]::Round($fileSizeBytes / 1KB, 2).ToString() + " KB"
        }
    } else { 
        "0 KB" 
    }
    
    return @{
        CpuUsage = $cpuUsage
        ProcessMemoryMB = $processMemoryMB
        MemoryUsagePercent = $memoryUsage
        DiskKBps = $diskActivity
        FileSize = $fileSize
    }
}

# Initialize error list - změna na global pro přístup z funkcí
$global:inaccessibleFiles = New-Object System.Collections.Generic.List[string]

# Get TimeStamp
function Get-TimeStamp {
    return "[{0:dd.MM.yy} {0:HH:mm:ss}]" -f (Get-Date)
}

# Verbose log function
function Write-VerboseLog {
    param ([string]$message)
    if ($VerboseLog) {
        Write-Host -ForegroundColor Yellow $message
    }
}

# Debug log function
function Write-DebugLog {
    param ([string]$message)
    if ($DebugLog) {
        Write-Host -ForegroundColor Magenta $message
    }
}

# Memory Debug log function - only enabled with -MemDebug parameter
function Write-MemoryDebug {
    param ([string]$message)
    if ($MemDebug) {
        Write-Host -ForegroundColor Cyan "[MEMORY DEBUG] $message"
    }
}

# Delete existing files if they exist
if (Test-Path -Path $JsonFilePath) {
    Remove-Item -Path $JsonFilePath -Force
    Write-DebugLog "Deleted existing JSON file: $JsonFilePath"
}

if (Test-Path -Path $ErrorLogFilePath) {
    Remove-Item -Path $ErrorLogFilePath -Force
    Write-DebugLog "Deleted existing error log file: $ErrorLogFilePath"
}

# Initialize the JSON file using File IO methods
try {
    # Použít UTF-8 encoding bez BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($JsonFilePath, "[", $utf8NoBom)
    Write-DebugLog "Initialized JSON file with opening bracket using System.IO.File with UTF-8 encoding."
}
catch {
    Write-DebugLog "Error initializing JSON file: $_"
    throw $_
}

# Function to append data to JSON file with enhanced debugging
function Append-ToJsonFile {
    param (
        [array]$Data
    )

    if ($Data.Count -eq 0) {
        Write-MemoryDebug "No data to write - skipping."
        return
    }

    Write-MemoryDebug "====== START APPEND FUNCTION ======"
    Write-MemoryDebug "Input Data count: $($Data.Count)"
    
    # Kontrola duplicit v datech
    $uniqueFullNames = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in $Data) {
        $uniqueFullNames.Add($item.FullName) | Out-Null
    }
    Write-MemoryDebug "Unique FullNames in Data: $($uniqueFullNames.Count) out of $($Data.Count) items"
    
    if ($uniqueFullNames.Count -ne $Data.Count) {
        Write-MemoryDebug "WARNING: $($Data.Count - $uniqueFullNames.Count) DUPLICATE ITEMS DETECTED IN DATA!"
        
        # Identifikace duplicit (omezeno na první 10 duplicit)
        $duplicateCount = 0
        $duplicateMap = @{}
        foreach ($item in $Data) {
            if ($duplicateMap.ContainsKey($item.FullName)) {
                $duplicateMap[$item.FullName]++
                if ($duplicateCount -lt 10) {
                    Write-MemoryDebug "  Duplicate #$($duplicateCount+1): $($item.FullName) (occurs $($duplicateMap[$item.FullName]) times)"
                    $duplicateCount++
                }
            } else {
                $duplicateMap[$item.FullName] = 1
            }
        }
        if ($duplicateCount -ge 10) {
            Write-MemoryDebug "  ...and more duplicates not shown"
        }
    }

    try {
        # Příprava dat pro serializaci
        $jsonLines = New-Object System.Collections.Generic.List[string]
        $problemFiles = New-Object System.Collections.Generic.List[string]
        
        foreach ($item in $Data) {
            try {
                $json = $item | ConvertTo-Json -Depth 3 -Compress
                $jsonLines.Add($json + ",")
            }
            catch {
                # Zaznamenat problematický soubor
                $problemFiles.Add("Error converting file to JSON: $($item.FullName) - $_")
                Write-MemoryDebug "Error converting file to JSON: $($item.FullName) - $_"
            }
        }
        
        Write-MemoryDebug "JSON lines prepared: $($jsonLines.Count) lines"
        
        # Zápis všech řádků najednou s ošetřením Unicode problémů
        if ($jsonLines.Count -gt 0) {
            Write-MemoryDebug "Writing $($jsonLines.Count) lines to file: $JsonFilePath"
            
            try {
                # Použít UTF-8 encoding pro zajištění podpory všech Unicode znaků
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::AppendAllLines($JsonFilePath, $jsonLines, $utf8NoBom)
                Write-MemoryDebug "File write complete"
            }
            catch {
                Write-MemoryDebug "Error writing to file: $_"
                
                # Pokud se vyskytl problém s Unicode znaky, zkusit zapsat po jednom řádku a přeskočit problematické
                Write-MemoryDebug "Attempting to write lines individually to bypass problem characters..."
                
                $fileStream = $null
                $streamWriter = $null
                
                try {
                    $fileStream = [System.IO.File]::Open($JsonFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
                    $streamWriter = New-Object System.IO.StreamWriter($fileStream, $utf8NoBom)
                    
                    $successCount = 0
                    foreach ($line in $jsonLines) {
                        try {
                            $streamWriter.WriteLine($line)
                            $successCount++
                        }
                        catch {
                            # Zaznamenat problém s Unicode znaky
                            Write-MemoryDebug "Error writing line with Unicode characters: $_"
                            $problemFiles.Add("Error writing line: $_")
                        }
                    }
                    Write-MemoryDebug "Successfully wrote $successCount out of $($jsonLines.Count) lines individually"
                }
                finally {
                    if ($streamWriter -ne $null) { 
                        $streamWriter.Close()
                        $streamWriter.Dispose()
                    }
                    if ($fileStream -ne $null) { 
                        $fileStream.Close()
                        $fileStream.Dispose()
                    }
                }
            }
        }
        
        # Přidat problematické soubory do logu
        if ($problemFiles.Count -gt 0) {
            $global:inaccessibleFiles.AddRange($problemFiles)
            Write-MemoryDebug "Added $($problemFiles.Count) problem files to inaccessible files log"
        }
        
        # Vyčištění
        $jsonLinesCount = $jsonLines.Count
        $jsonLines.Clear()
        Write-MemoryDebug "Cleared jsonLines collection (Before: $jsonLinesCount, After: $($jsonLines.Count))"
        $jsonLines = $null
        Write-MemoryDebug "Set jsonLines to null"
        
        $problemFiles.Clear()
        $problemFiles = $null
    }
    catch {
        Write-MemoryDebug "ERROR in Append-ToJsonFile: $_"
        
        # Zaznamenání chyby do log souboru
        $global:inaccessibleFiles.Add("Error in Append-ToJsonFile: $_")
        
        # Přehodíme chybu vyšší úrovni
        throw $_
    }
    
    Write-MemoryDebug "====== END APPEND FUNCTION ======"
}

# Function to finalize the JSON file
function Complete-JsonFile {
    try {
        Write-MemoryDebug "Finalizing JSON file..."
        
        # Použít nízkoúrovňové čtení/zápis pro větší kontrolu
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        
        # Přečíst obsah souboru
        $content = [System.IO.File]::ReadAllText($JsonFilePath)
        
        if ($content) {
            # Odstranit koncové čárky a přidat uzavírací závorku
            $content = $content.TrimEnd(",`r`n") + "]"
            [System.IO.File]::WriteAllText($JsonFilePath, $content, $utf8NoBom)
            Write-MemoryDebug "JSON file finalized successfully"
        } else {
            [System.IO.File]::WriteAllText($JsonFilePath, "[]", $utf8NoBom)
            Write-MemoryDebug "Empty JSON file finalized as empty array"
        }
    }
    catch {
        Write-MemoryDebug "Error finalizing JSON file: $_"
        $global:inaccessibleFiles.Add("Error finalizing JSON file: $_")
        
        # Zkusíme alternativní přístup pro finalizaci
        try {
            Write-MemoryDebug "Attempting alternative file finalization..."
            $fileStream = [System.IO.File]::Open($JsonFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            $streamWriter = New-Object System.IO.StreamWriter($fileStream, $utf8NoBom)
            $streamWriter.Write("]")
            $streamWriter.Close()
            $fileStream.Close()
            Write-MemoryDebug "Alternative finalization succeeded"
        }
        catch {
            Write-MemoryDebug "Alternative finalization also failed: $_"
            $global:inaccessibleFiles.Add("Error in alternative finalization: $_")
        }
    }
}

# Initialize file processing
$fileBlock = New-Object System.Collections.Generic.List[PSObject]
$fileCounter = 0
$blockCounter = 0
$dirsToProcess = New-Object System.Collections.Generic.Queue[string]
$dirsToProcess.Enqueue($FolderPath)

# Track processed directories and files
$processedDirs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
$processedFiles = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)

Write-MemoryDebug "Starting file enumeration in folder: $FolderPath"
Write-MemoryDebug "System is using BlockSize of $BlockSize"

while ($dirsToProcess.Count -gt 0) {
    $currentDir = $dirsToProcess.Dequeue()
    
    # Skip if already processed
    if ($processedDirs.Contains($currentDir)) {
        Write-VerboseLog "Skipping already processed directory: $currentDir"
        continue
    }
    
    # Mark as processed
    $processedDirs.Add($currentDir) | Out-Null
    
    Write-VerboseLog "Processing directory: $currentDir ($($dirsToProcess.Count) directories in queue)"

    # Process files
    try {
        $files = Get-ChildItem -LiteralPath $currentDir -File -ErrorAction SilentlyContinue
        
        # Write-MemoryDebug "Found $($files.Count) files in directory $currentDir"
        
        foreach ($file in $files) {
            try {
                # Skip if already processed
                if ($processedFiles.Contains($file.FullName)) {
                    Write-VerboseLog "Skipping already processed file: $($file.FullName)"
                    continue
                }
                
                # Mark as processed
                $processedFiles.Add($file.FullName) | Out-Null
                
                $fileInfo = [PSCustomObject]@{
                    Name              = $file.Name
                    BaseName          = $file.BaseName
                    Length            = $file.Length
                    DirectoryName     = $file.DirectoryName
                    IsReadOnly        = $file.IsReadOnly
                    Exist             = $file.Exists
                    FullName          = $file.FullName
                    Extension         = $file.Extension
                    CreationTimeUtc   = $file.CreationTimeUtc
                    LastAccessTimeUtc = $file.LastAccessTimeUtc
                    LastWriteTimeUtc  = $file.LastWriteTimeUtc
                    Attributes        = $file.Attributes
                }
                
                $fileBlock.Add($fileInfo)
                $fileCounter++

                # Log progress
                if ($fileCounter % $BlockSize -eq 0) {
                    $elapsedSinceLastBlock = $lastBlockTime.Elapsed.TotalSeconds
                    $filesPerSecond = [math]::Round($BlockSize / $elapsedSinceLastBlock, 2)
                    
                    # Základní výstup
                    $outputMessage = "$(Get-TimeStamp) Processed $fileCounter files... ($filesPerSecond files/second)"
                    
                    # Přidání informací o výkonu, pokud je zapnutý monitoring
                    if ($PerfMon) {
                        $metrics = Get-SystemMetrics
                        $outputMessage += " | CPU: $($metrics.CpuUsage)% | RAM: PS:$($metrics.ProcessMemoryMB)MB Sys:$($metrics.MemoryUsagePercent)% | Disk: $($metrics.DiskKBps) KB/s | JSON: $($metrics.FileSize)"
                    }
                    
                    # Přidání informací o adresářích
                    $outputMessage += " | Dirs: $($processedDirs.Count) | Queue: $($dirsToProcess.Count)"
                    
                    Write-Host -ForegroundColor Magenta $outputMessage
                    
                    # Resetujeme časovač pro další blok
                    $lastBlockTime.Restart()
                }

                Write-VerboseLog "Processed file: $($file.FullName)"
                
                # Write block to file if full
                if ($fileBlock.Count -ge $BlockSize) {
                    $blockCounter++
                    Write-MemoryDebug "Block $blockCounter is full with $($fileBlock.Count) items - preparing to write"
                    
                    # Create a deep copy of the current block
                    $itemsToWrite = New-Object System.Collections.Generic.List[PSObject]
                    foreach ($item in $fileBlock) {
                        $itemsToWrite.Add($item)
                    }
                    Write-MemoryDebug "Created an independent copy with $($itemsToWrite.Count) items"
                    
                    # Check if the copy contains all the expected items
                    if ($itemsToWrite.Count -ne $fileBlock.Count) {
                        Write-MemoryDebug "WARNING: Copy contains different number of items than original"
                    }
                    
                    # Get current memory usage before clearing
                    if ($PerfMon) {
                        $currentProcess.Refresh()
                        $beforeClearMemoryMB = [math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
                        Write-MemoryDebug "Memory usage before clearing: $beforeClearMemoryMB MB"
                    }
                    
                    # Clear the original block
                    $originalCount = $fileBlock.Count
                    $fileBlock.Clear()
                    Write-MemoryDebug "Cleared original fileBlock. Before: $originalCount, After: $($fileBlock.Count)"
                    
                    # Check memory after clearing
                    if ($PerfMon) {
                        $currentProcess.Refresh()
                        $afterClearMemoryMB = [math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
                        Write-MemoryDebug "Memory usage after clearing: $afterClearMemoryMB MB (Change: $([math]::Round($afterClearMemoryMB - $beforeClearMemoryMB, 2)) MB)"
                    }
                    
                    # Write the copied data
                    Append-ToJsonFile -Data $itemsToWrite
                    
                    # Remove reference to copied data
                    Write-MemoryDebug "Removing reference to the copied data ($($itemsToWrite.Count) items)"
                    $itemsToWrite.Clear()
                    $itemsToWrite = $null
                    
                    # Force garbage collection
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    
                    # Check memory after GC
                    if ($PerfMon) {
                        $currentProcess.Refresh()
                        $afterGCMemoryMB = [math]::Round($currentProcess.WorkingSet64 / 1MB, 2)
                        Write-MemoryDebug "Memory usage after GC: $afterGCMemoryMB MB (Change from after clear: $([math]::Round($afterGCMemoryMB - $afterClearMemoryMB, 2)) MB)"
                    }
                    
                    Write-VerboseLog "Block $blockCounter written to file and memory cleared"
                    
                    # Check fileBlock size after all operations
                    Write-MemoryDebug "FileBlock size after all operations: $($fileBlock.Count)"
                    
                    # Periodically clear processed files hash to prevent excessive memory usage
                    if ($processedFiles.Count -gt 100000) {
                        $oldCount = $processedFiles.Count
                        $processedFiles.Clear()
                        Write-MemoryDebug "Cleared processed files HashSet (was $oldCount entries, now $($processedFiles.Count))"
                        [System.GC]::Collect()
                        [System.GC]::WaitForPendingFinalizers()
                    }
                }
            } catch {
                $inaccessibleFiles.Add($file.FullName)
                Write-VerboseLog "Inaccessible file: $($file.FullName)"
                Write-MemoryDebug "Error accessing file: $($file.FullName) - $_"
            }
        }

        # Process subdirectories
        $subdirectories = Get-ChildItem -LiteralPath $currentDir -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $subdirectories) {
            if (-not $processedDirs.Contains($dir.FullName)) {
                $dirsToProcess.Enqueue($dir.FullName)
            }
        }
    } catch {
        $inaccessibleFiles.Add("Error accessing directory: $currentDir - $_")
        Write-MemoryDebug "Error accessing directory: $currentDir - $_"
    }
}

# Write remaining files
if ($fileBlock.Count -gt 0) {
    Write-MemoryDebug "====== PROCESSING FINAL BLOCK ======"
    Write-MemoryDebug "Final block has $($fileBlock.Count) items"
    
    # Create a deep copy of the remaining items
    $remainingItems = New-Object System.Collections.Generic.List[PSObject]
    foreach ($item in $fileBlock) {
        $remainingItems.Add($item)
    }
    Write-MemoryDebug "Created final copy with $($remainingItems.Count) items"
    
    # Clear original block
    $originalCount = $fileBlock.Count
    $fileBlock.Clear()
    Write-MemoryDebug "Cleared original fileBlock (Before: $originalCount, After: $($fileBlock.Count))"
    $fileBlock = $null
    Write-MemoryDebug "Set fileBlock to null"
    
    # Write the copy
    Append-ToJsonFile -Data $remainingItems
    
    # Clear the copy
    $copyCount = $remainingItems.Count
    $remainingItems.Clear()
    Write-MemoryDebug "Cleared copy (Before: $copyCount, After: $($remainingItems.Count))"
    $remainingItems = $null
    Write-MemoryDebug "Set remainingItems to null"
    Write-MemoryDebug "====== END PROCESSING FINAL BLOCK ======"
}

# Finalize JSON file
Write-MemoryDebug "====== FINALIZING JSON FILE ======"
Complete-JsonFile
Write-MemoryDebug "====== JSON FILE FINALIZED ======"

# Ensure all references are cleared
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

# End timer
$stopwatch.Stop()

# Save inaccessible files to log
Set-Content -Path $ErrorLogFilePath -Value ($global:inaccessibleFiles -join "`n")
Write-MemoryDebug "Saved inaccessible file paths to log file: $ErrorLogFilePath ($($global:inaccessibleFiles.Count) entries)"

# Print results
$totalFiles = $fileCounter
$elapsedTime = $stopwatch.Elapsed.TotalSeconds
$filesPerSecond = [math]::Round($totalFiles / $elapsedTime, 2)

Write-Host ""
Write-Host "------------------------------------------------------------------------" -ForegroundColor Green
Write-Host -ForegroundColor Cyan "Summary of the operation:"
Write-Host -ForegroundColor Green "[*] Total files processed: $totalFiles"
Write-Host -ForegroundColor Green "[*] Total directories processed: $($processedDirs.Count)"
Write-Host -ForegroundColor Green "[*] Total blocks written: $blockCounter"
Write-Host -ForegroundColor Green "[*] Elapsed time (seconds): $elapsedTime"
Write-Host -ForegroundColor Green "[*] Files per second: $filesPerSecond"
Write-Host -ForegroundColor Green "[*] File information saved to: $JsonFilePath"
Write-Host -ForegroundColor Green "[*] Inaccessible file paths saved to: $ErrorLogFilePath"
Write-Host "------------------------------------------------------------------------" -ForegroundColor Green
Write-Host ""

# Run a final validation check on the output file
try {
    $jsonFileInfo = Get-Item -Path $JsonFilePath
    $jsonFileSize = [math]::Round($jsonFileInfo.Length / 1MB, 2)
    Write-MemoryDebug "Output file size: $jsonFileSize MB"
    
    # Check if file is valid JSON
    Write-MemoryDebug "Validating JSON structure..."
    
    # Bezpečnější kontrola prvních a posledních znaků
    try {
        $fileStream = [System.IO.File]::Open($JsonFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($fileStream)
        
        # Kontrola prvních 10 znaků
        $firstChars = ""
        for ($i = 0; $i -lt 10 -and -not $reader.EndOfStream; $i++) {
            $firstChars += [char]$reader.Read()
        }
        
        Write-MemoryDebug "First characters: $firstChars"
        
        # Přesun na konec souboru pro kontrolu posledních znaků
        if ($fileStream.Length -gt 20) {
            $fileStream.Seek(-10, [System.IO.SeekOrigin]::End) | Out-Null
        } else {
            $fileStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
        }
        
        # Čtení posledních znaků
        $lastChars = ""
        while (-not $reader.EndOfStream) {
            $lastChars += [char]$reader.Read()
        }
        
        Write-MemoryDebug "Last characters: $lastChars"
        
        $reader.Close()
        $fileStream.Close()
        
        if ($firstChars.StartsWith("[") -and $lastChars.EndsWith("]")) {
            Write-MemoryDebug "JSON structure appears valid (starts with [ and ends with ])"
        } else {
            Write-MemoryDebug "WARNING: JSON structure may be invalid! First char: '$firstChars', Last char: '$lastChars'"
        }
    }
    catch {
        Write-MemoryDebug "Error reading file for validation: $_"
    }
    finally {
        if ($reader -ne $null) { $reader.Dispose() }
        if ($fileStream -ne $null) { $fileStream.Dispose() }
    }
} catch {
    Write-MemoryDebug "Error validating output file: $_"
}

Write-MemoryDebug "DEBUG SCRIPT COMPLETED"