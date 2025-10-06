# Logging Module

# Module-level variables
$script:LogFile = $null
$script:RepoRoot = $null

function Get-RelativePath {
    param (
        [string]$Path
    )
    
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    
    # Initialize repo root if not set
    if (-not $script:RepoRoot) {
        $currentPath = Get-Location
        while ($currentPath -and -not (Test-Path (Join-Path $currentPath '.git'))) {
            $currentPath = Split-Path $currentPath -Parent
        }
        $script:RepoRoot = $currentPath
    }
    
    if ($script:RepoRoot -and $Path.StartsWith($script:RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $Path.Substring($script:RepoRoot.Length).TrimStart('\', '/')
        return ".\$relativePath"
    }
    
    return $Path
}

function Initialize-Logging {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )

    if ([string]::IsNullOrEmpty($ScriptPath)) {
        throw "ScriptPath cannot be empty"
    }

    # Get the tools directory (parent of the script's parent)
    $scriptDir = Split-Path $ScriptPath -Parent
    if ([string]::IsNullOrEmpty($scriptDir)) {
        throw "Could not determine script directory from path: $ScriptPath"
    }

    # Set up log file path in the tool's own logs directory (sibling of the script)
    $logsDir = Join-Path $scriptDir "logs"
    $logFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) + ".log"
    $script:LogFile = Join-Path $logsDir $logFileName
    $logDir = $logsDir

    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Rotate logs if file exceeds 10MB
    if (Test-Path $script:LogFile) {
        $logSize = (Get-Item $script:LogFile).Length
        if ($logSize -gt 10MB) {
            $backupLog = "$script:LogFile.1"
            if (Test-Path $backupLog) {
                Remove-Item $backupLog -Force
            }
            Rename-Item $script:LogFile $backupLog
        }
    }
}

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'DEBUG'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"

    # Write to console with color
    switch ($Level) {
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'INFO'  { Write-Host $Message -ForegroundColor Cyan }
        'DEBUG' { Write-Host $Message -ForegroundColor Gray }
    }

    # Write to log file
    if ($null -ne $script:LogFile -and -not [string]::IsNullOrEmpty($script:LogFile)) {
        try {
            if (-not (Test-Path (Split-Path $script:LogFile -Parent))) {
                New-Item -ItemType Directory -Path (Split-Path $script:LogFile -Parent) -Force | Out-Null
            }
            Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
            Write-Warning "Log file path: $script:LogFile"
        }
    } else {
        Write-Warning "Log file path not initialized. Call Initialize-Logging first."
        Write-Debug "Current script location: $($MyInvocation.ScriptName)"
    }
}

# Export the functions to make them available when the module is imported
Export-ModuleMember -Function Initialize-Logging, Write-Log
