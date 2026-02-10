# Image to Markdown Converter using Gemini 2.5 Flash

param (
    [Parameter()]
    [string[]]$Paths
)

# Import logging module
$moduleDir = Join-Path $PSScriptRoot "..\common"
Import-Module (Join-Path $moduleDir "Write-Log.psm1") -Force

# Initialize logging
Initialize-Logging $PSCommandPath

# Check if GOOGLE_GENAI_API_KEY environment variable is set
if (-not $env:GOOGLE_GENAI_API_KEY) {
    Write-Log "GOOGLE_GENAI_API_KEY environment variable is not set" -Level ERROR
    Write-Log "Please set it with: `$env:GOOGLE_GENAI_API_KEY = 'your_api_key_here'" -Level WARN
    exit 1
}

# Supported image formats and their MIME types
$SupportedFormats = @{
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.webp' = 'image/webp'
    '.heic' = 'image/heic'
    '.heif' = 'image/heif'
}

# Base URL for Gemini API
$BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
$UPLOAD_BASE_URL = "https://generativelanguage.googleapis.com/upload/v1beta"

# Function to convert Image to markdown using inline data (for smaller files)
function Convert-ImageInline {
    param(
        [string]$ImagePath,
        [string]$OutputPath
    )

    Write-Log "Converting '$ImagePath' to markdown using inline method..." -Level INFO

    # Base64 encode the Image
    $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
    $encodedImage = [System.Convert]::ToBase64String($imageBytes)

    # Create the prompt text (escaped properly)
    $promptText = "Please convert this image to clean, well-formatted markdown. If the image contains text, transcribe it accurately. If it contains structured information like lists, tables, or code, preserve the structure. For diagrams or user interfaces, describe them in detail. Ensure the final markdown is readable and well-organized."

    # Prepare the request body
    $requestBody = @{
        contents = @(
            @{
                parts = @(
                    @{
                        inline_data = @{
                            mime_type = $SupportedFormats[$fileInfo.Extension.ToLower()]
                            data = $encodedImage
                        }
                    },
                    @{
                        text = $promptText
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        # Make the API call
        $response = Invoke-RestMethod -Uri "$BASE_URL/models/gemini-3-flash-preview:generateContent?key=$env:GOOGLE_GENAI_API_KEY" `
            -Method Post `
            -ContentType "application/json" `
            -Body $requestBody

        # Extract and save the markdown content
        if ($response.candidates -and $response.candidates[0].content.parts -and $response.candidates[0].content.parts[0].text) {
            $markdownContent = $response.candidates[0].content.parts[0].text
            [System.IO.File]::WriteAllText($OutputPath, $markdownContent, [System.Text.Encoding]::UTF8)
            Write-Log "Successfully converted '$ImagePath' to '$OutputPath'" -Level INFO
        } else {
            Write-Log "Failed to convert '$ImagePath'" -Level ERROR
            Write-Log "API Response: $($response | ConvertTo-Json -Depth 5)" -Level DEBUG
        }
    }
    catch {
        Write-Log "Error converting '$ImagePath': $_" -Level ERROR
    }
}

# Function to convert Image using File API (for larger files)
function Convert-ImageFileApi {
    param(
        [string]$ImagePath,
        [string]$OutputPath
    )

    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
    Write-Log "Converting $ImagePath to markdown using File API..." -Level INFO

    $fileInfo = Get-Item $ImagePath
    $numBytes = $fileInfo.Length

    try {
        # Step 1: Initial resumable request
        $uploadHeaders = @{
            "X-Goog-Upload-Protocol" = "resumable"
            "X-Goog-Upload-Command" = "start"
            "X-Goog-Upload-Header-Content-Length" = $numBytes.ToString()
            "X-Goog-Upload-Header-Content-Type" = $SupportedFormats[$fileInfo.Extension.ToLower()]
            "Content-Type" = "application/json"
        }

        $uploadBody = @{
            file = @{
                display_name = $displayName
            }
        } | ConvertTo-Json -Depth 5

        $uploadResponse = Invoke-WebRequest -Uri "$UPLOAD_BASE_URL/files?key=$env:GOOGLE_GENAI_API_KEY" `
            -Method Post `
            -Headers $uploadHeaders `
            -Body $uploadBody

        # Extract upload URL from response headers
        $uploadUrl = $uploadResponse.Headers["x-goog-upload-url"]

        # Step 2: Upload the actual file
        $fileBytes = [System.IO.File]::ReadAllBytes($ImagePath)
        $uploadFileHeaders = @{
            "Content-Length" = $numBytes.ToString()
            "X-Goog-Upload-Offset" = "0"
            "X-Goog-Upload-Command" = "upload, finalize"
        }

        $fileResponse = Invoke-RestMethod -Uri $uploadUrl `
            -Method Post `
            -Headers $uploadFileHeaders `
            -Body $fileBytes

        $fileUri = $fileResponse.file.uri
        Write-Log "File uploaded with URI: $fileUri" -Level INFO

        # Create the prompt text (escaped properly)
        $promptText = "Please convert this image to clean, well-formatted markdown. If the image contains text, transcribe it accurately. If it contains structured information like lists, tables, or code, preserve the structure. For diagrams or user interfaces, describe them in detail. Ensure the final markdown is readable and well-organized."

        # Step 3: Generate content using the uploaded file
        $generateBody = @{
            contents = @(
                @{
                    parts = @(
                        @{
                            text = $promptText
                        },
                        @{
                            file_data = @{
                                mime_type = $SupportedFormats[$fileInfo.Extension.ToLower()]
                                file_uri = $fileUri
                            }
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri "$BASE_URL/models/gemini-3-flash-preview:generateContent?key=$env:GOOGLE_GENAI_API_KEY" `
            -Method Post `
            -ContentType "application/json" `
            -Body $generateBody

        # Extract and save the markdown content
        if ($response.candidates -and $response.candidates[0].content.parts -and $response.candidates[0].content.parts[0].text) {
            $markdownContent = $response.candidates[0].content.parts[0].text
            [System.IO.File]::WriteAllText($OutputPath, $markdownContent, [System.Text.Encoding]::UTF8)
            Write-Log "Successfully converted '$ImagePath' to '$OutputPath'" -Level INFO
        } else {
            Write-Log "Failed to convert '$ImagePath'" -Level ERROR
            Write-Log "API Response: $($response | ConvertTo-Json -Depth 5)" -Level DEBUG
        }
    }
    catch {
        Write-Log "Error converting '$ImagePath': $_" -Level ERROR
    }
}

# Function to check if markdown file already exists
function Test-MarkdownExists {
    param([string]$ImagePath)

    $mdPath = [System.IO.Path]::ChangeExtension($ImagePath, '.md')
    return Test-Path $mdPath
}

# Function to convert a single Image
function Convert-Image {
    param([string]$ImagePath)

    $mdPath = [System.IO.Path]::ChangeExtension($ImagePath, '.md')

    # Check if markdown already exists
    if (Test-MarkdownExists $ImagePath) {
        Write-Log "SKIPPING: $ImagePath - markdown file already exists" -Level WARN
        return
    }

    # Check file size to determine method (3MB threshold)
    $fileInfo = Get-Item $ImagePath
    $maxInlineSize = 3 * 1024 * 1024  # 3MB

    if ($fileInfo.Length -lt $maxInlineSize) {
        Convert-ImageInline -ImagePath $ImagePath -OutputPath $mdPath
    } else {
        Convert-ImageFileApi -ImagePath $ImagePath -OutputPath $mdPath
    }

    # Add delay to avoid rate limiting
    Start-Sleep -Seconds 2
}

# Function to convert a directory
function Convert-Directory {
    param([string]$DirPath)

    Write-Log "Processing directory: $DirPath" -Level INFO
    Get-ChildItem -Path $DirPath -Recurse | 
        Where-Object { $SupportedFormats.ContainsKey($_.Extension.ToLower()) } |
        ForEach-Object {
            Convert-Image -ImagePath $_.FullName
        }
}

# Main execution
Write-Log "Finding image files to convert..." -Level INFO

if ($Paths) {
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            $item = Get-Item $path
            if ($item.PSIsContainer) {
                # If path is a directory, process all supported image files in it
                Convert-Directory $path
            }
            elseif ($SupportedFormats.ContainsKey($item.Extension.ToLower())) {
                # If path is a supported image file, process it
                Convert-Image -ImagePath $item.FullName
            }
            else {
                Write-Log "SKIPPING: $path - not a supported image file or directory. Supported formats: $($SupportedFormats.Keys -join ', ')" -Level WARN
            }
        }
        else {
            Write-Log "SKIPPING: $path - path does not exist" -Level ERROR
        }
    }
}
else {
    # Default behavior - scan all directories in root
    Write-Log "No paths specified. Scanning all directories in repository root..." -Level INFO
    Get-ChildItem -Directory | ForEach-Object {
        Convert-Directory $_.FullName
    }
}

Write-Log "Image to Markdown conversion complete!" -Level INFO
