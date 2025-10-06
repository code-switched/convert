# Image to Markdown Conversion Tools

This directory contains tools for converting image files (PNG) to markdown format using Google's Gemini 2.5 Flash AI model. The tools can process both small and large images, handling them efficiently based on their size.

## Prerequisites

- Google Gemini API key (environment variable: `GOOGLE_GENAI_API_KEY`)
- For PowerShell script:
  - PowerShell 5.1 or later
- For Bash script:
  - bash shell
  - curl
  - jq (for JSON processing)
  - base64 command (GNU or FreeBSD variants supported)

## Available Tools

### PowerShell Script: `convert_image_to_markdown.ps1`

Convert PNG images to markdown using PowerShell. Supports Windows environments.

```powershell
# Convert a single image
.\convert_image_to_markdown.ps1 -Paths "path/to/image.png"

# Convert multiple images
.\convert_image_to_markdown.ps1 -Paths "image1.png", "image2.png"

# Convert all PNGs in a directory
.\convert_image_to_markdown.ps1 -Paths "path/to/directory"

# Convert all PNGs in multiple directories
.\convert_image_to_markdown.ps1 -Paths "dir1", "dir2"

# Convert all PNGs in all subdirectories (default behavior)
.\convert_image_to_markdown.ps1
```

### Bash Script: `convert_images_to_markdown.sh`

Convert PNG images to markdown using Bash. Supports Linux, macOS, and Unix-like environments.

```bash
# Make the script executable
chmod +x convert_images_to_markdown.sh

# Convert a single image
./convert_images_to_markdown.sh path/to/image.png

# Convert multiple images
./convert_images_to_markdown.sh image1.png image2.png

# Convert all PNGs in a directory
./convert_images_to_markdown.sh path/to/directory

# Convert all PNGs in multiple directories
./convert_images_to_markdown.sh dir1 dir2

# Convert all PNGs in all subdirectories (default behavior)
./convert_images_to_markdown.sh
```

## Features

- Handles both small and large image files
  - Uses inline data for files under 3MB
  - Uses File API for larger files
- Supports recursive directory processing
- Maintains original file structure
- Skips already converted files
- Provides detailed progress and error reporting
- Color-coded console output (PowerShell version)
- Cross-platform compatibility
- Rate limiting protection (2-second delay between conversions)

## Output

For each processed image:

- Creates a markdown file with the same name (e.g., `image.png` → `image.md`)
- Preserves the directory structure
- Includes:
  - Accurate text transcription
  - Structure preservation (lists, tables, code)
  - Detailed descriptions of diagrams and UI elements
  - Well-organized markdown formatting

## Error Handling

- Checks for API key presence
- Validates file existence and type
- Reports conversion failures
- Handles network issues gracefully
- Supports both GNU and FreeBSD environments

## Best Practices

1. Set your API key as an environment variable:

   ```bash
   # For Bash
   export GOOGLE_GENAI_API_KEY='your_key_here'
   
   # For PowerShell
   $env:GOOGLE_GENAI_API_KEY = 'your_key_here'
   ```

2. For large directories, consider processing in batches to manage API usage

3. Monitor the output for any conversion failures

4. Check generated markdown files for accuracy

## Limitations

- Currently supports PNG files only
- Maximum file size limited by available memory and API constraints
- Rate limited to prevent API overuse
- Requires internet connection for API access
