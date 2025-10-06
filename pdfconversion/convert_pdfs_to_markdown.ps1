# PDF to Markdown Converter using Gemini 2.5 Flash

param (
    [Parameter()]
    [string[]]$Paths
)

# Check if GOOGLE_GENAI_API_KEY environment variable is set
if (-not $env:GOOGLE_GENAI_API_KEY) {
    Write-Host "Error: GOOGLE_GENAI_API_KEY environment variable is not set" -ForegroundColor Red
    Write-Host "Please set it with: `$env:GOOGLE_GENAI_API_KEY = 'your_api_key_here'" -ForegroundColor Yellow
    exit 1
}

# Base URL for Gemini API
$BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

# Function to convert PDF to markdown using inline data (for smaller files)
function Convert-PdfInline {
    param(
        [string]$PdfPath,
        [string]$OutputPath
    )

    Write-Host "Converting $PdfPath to markdown using inline method..." -ForegroundColor Blue

    # Base64 encode the PDF
    $pdfBytes = [System.IO.File]::ReadAllBytes($PdfPath)
    $encodedPdf = [System.Convert]::ToBase64String($pdfBytes)

    # Create the prompt text (escaped properly)
    $promptText = "Please convert this PDF document to clean, well-formatted markdown. Preserve all important information, structure, headings, lists, and formatting. Use appropriate markdown syntax for headings, lists, code blocks if any, and emphasis. Make sure the output is readable and well-organized."

    # Prepare the request body
    $requestBody = @{
        contents = @(
            @{
                parts = @(
                    @{
                        inline_data = @{
                            mime_type = "application/pdf"
                            data = $encodedPdf
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
        $response = Invoke-RestMethod -Uri "$BASE_URL/models/gemini-2.5-flash:generateContent?key=$env:GOOGLE_GENAI_API_KEY" `
            -Method Post `
            -ContentType "application/json" `
            -Body $requestBody

        # Extract and save the markdown content
        if ($response.candidates -and $response.candidates[0].content.parts -and $response.candidates[0].content.parts[0].text) {
            $markdownContent = $response.candidates[0].content.parts[0].text
            [System.IO.File]::WriteAllText($OutputPath, $markdownContent, [System.Text.Encoding]::UTF8)
            Write-Host "SUCCESS: Converted $PdfPath to $OutputPath" -ForegroundColor Green
        } else {
            Write-Host "FAILED: Could not convert $PdfPath" -ForegroundColor Red
            Write-Host "Response: $($response | ConvertTo-Json -Depth 5)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "ERROR: Converting ${PdfPath}: $_" -ForegroundColor Red
    }
}

# Function to convert PDF using File API (for larger files)
function Convert-PdfFileApi {
    param(
        [string]$PdfPath,
        [string]$OutputPath
    )

    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($PdfPath)
    Write-Host "Converting $PdfPath to markdown using File API..." -ForegroundColor Blue

    $fileInfo = Get-Item $PdfPath
    $numBytes = $fileInfo.Length

    try {
        # Step 1: Initial resumable request
        $uploadHeaders = @{
            "X-Goog-Upload-Protocol" = "resumable"
            "X-Goog-Upload-Command" = "start"
            "X-Goog-Upload-Header-Content-Length" = $numBytes.ToString()
            "X-Goog-Upload-Header-Content-Type" = "application/pdf"
            "Content-Type" = "application/json"
        }

        $uploadBody = @{
            file = @{
                display_name = $displayName
            }
        } | ConvertTo-Json -Depth 5

        $uploadResponse = Invoke-WebRequest -Uri "$BASE_URL/upload/v1beta/files?key=$env:GOOGLE_GENAI_API_KEY" `
            -Method Post `
            -Headers $uploadHeaders `
            -Body $uploadBody

        # Extract upload URL from response headers
        $uploadUrl = $uploadResponse.Headers["x-goog-upload-url"]

        # Step 2: Upload the actual file
        $fileBytes = [System.IO.File]::ReadAllBytes($PdfPath)
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
        Write-Host "File uploaded with URI: $fileUri" -ForegroundColor Cyan

        # Create the prompt text (escaped properly)
        $promptText = "Please convert this PDF document to clean, well-formatted markdown. Preserve all important information, structure, headings, lists, and formatting. Use appropriate markdown syntax for headings, lists, code blocks if any, and emphasis. Make sure the output is readable and well-organized."

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
                                mime_type = "application/pdf"
                                file_uri = $fileUri
                            }
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri "$BASE_URL/models/gemini-2.5-flash:generateContent?key=$env:GOOGLE_GENAI_API_KEY" `
            -Method Post `
            -ContentType "application/json" `
            -Body $generateBody

        # Extract and save the markdown content
        if ($response.candidates -and $response.candidates[0].content.parts -and $response.candidates[0].content.parts[0].text) {
            $markdownContent = $response.candidates[0].content.parts[0].text
            [System.IO.File]::WriteAllText($OutputPath, $markdownContent, [System.Text.Encoding]::UTF8)
            Write-Host "SUCCESS: Converted $PdfPath to $OutputPath" -ForegroundColor Green
        } else {
            Write-Host "FAILED: Could not convert $PdfPath" -ForegroundColor Red
            Write-Host "Response: $($response | ConvertTo-Json -Depth 5)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "ERROR: Converting ${PdfPath}: $_" -ForegroundColor Red
    }
}

# Function to check if markdown file already exists
function Test-MarkdownExists {
    param([string]$PdfPath)

    $mdPath = $PdfPath -replace '\.pdf$', '.md'
    return Test-Path $mdPath
}

# Function to convert a single PDF
function Convert-Pdf {
    param([string]$PdfPath)

    $mdPath = $PdfPath -replace '\.pdf$', '.md'

    # Check if markdown already exists
    if (Test-MarkdownExists $PdfPath) {
        Write-Host "SKIPPING: $PdfPath - markdown file already exists" -ForegroundColor Yellow
        return
    }

    # Check file size to determine method (15MB threshold)
    $fileInfo = Get-Item $PdfPath
    $maxInlineSize = 15 * 1024 * 1024  # 15MB

    if ($fileInfo.Length -lt $maxInlineSize) {
        Convert-PdfInline -PdfPath $PdfPath -OutputPath $mdPath
    } else {
        Convert-PdfFileApi -PdfPath $PdfPath -OutputPath $mdPath
    }

    # Add delay to avoid rate limiting
    Start-Sleep -Seconds 2
}

# Function to convert a directory
function Convert-Directory {
    param([string]$DirPath)
    
    Write-Host "Processing directory: $DirPath" -ForegroundColor Cyan
    Get-ChildItem "$DirPath\*.pdf" -Recurse | ForEach-Object {
        Convert-Pdf -PdfPath $_.FullName
    }
}

# Main execution
Write-Host "Finding PDF files to convert..." -ForegroundColor Cyan

if ($Paths) {
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            $item = Get-Item $path
            if ($item.PSIsContainer) {
                # If path is a directory, process all PDFs in it
                Convert-Directory $path
            }
            elseif ($item.Extension -eq '.pdf') {
                # If path is a PDF file, process it
                Convert-Pdf -PdfPath $item.FullName
            }
            else {
                Write-Host "SKIPPING: $path - not a PDF file or directory" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "SKIPPING: $path - path does not exist" -ForegroundColor Red
        }
    }
}
else {
    # Default behavior - scan all directories in root
    Write-Host "No paths specified. Scanning all directories in repository root..." -ForegroundColor Cyan
    Get-ChildItem -Directory | ForEach-Object {
        Convert-Directory $_.FullName
    }
}

Write-Host "PDF to Markdown conversion complete!" -ForegroundColor Green 