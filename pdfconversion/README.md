# PDF to Markdown Converter

This directory contains scripts to convert PDF files to markdown format using Google's Gemini 2.5 Pro API.

## Prerequisites

1. **Google API Key**: You need a Google API key with access to the Gemini API
   - Get one from: <https://aistudio.google.com/app/apikey>
   - The API has generous free limits for most use cases

2. **Required Tools**:
   - **Windows**: PowerShell
   - **Linux/macOS**: Bash, `curl`, `jq`, `base64`

## Setup

### Windows (PowerShell)

```powershell
# Set your API key (replace with your actual key)
$env:GOOGLE_GENAI_API_KEY = "your_api_key_here"

# Run the conversion script
.\convert_pdfs_to_markdown.ps1
```

### Linux/macOS (Bash)

```bash
# Set your API key (replace with your actual key)
export GOOGLE_GENAI_API_KEY="your_api_key_here"

# Make the script executable
chmod +x convert_pdfs_to_markdown.sh

# Run the conversion script
./convert_pdfs_to_markdown.sh
```

## Usage

The scripts can be used in multiple ways:

### Default Mode

Running without arguments will scan all directories in the repository root:

```powershell
# PowerShell
.\convert_pdfs_to_markdown.ps1

# Bash
./convert_pdfs_to_markdown.sh
```

### Specific Files

Convert one or more specific PDF files:

```powershell
# PowerShell
.\convert_pdfs_to_markdown.ps1 -Paths "path/to/file1.pdf","path/to/file2.pdf"

# Bash
./convert_pdfs_to_markdown.sh "path/to/file1.pdf" "path/to/file2.pdf"
```

### Specific Directories

Process all PDFs in one or more directories:

```powershell
# PowerShell
.\convert_pdfs_to_markdown.ps1 -Paths "path/to/dir1","path/to/dir2"

# Bash
./convert_pdfs_to_markdown.sh "path/to/dir1" "path/to/dir2"
```

### Mixed Mode

Process a combination of files and directories:

```powershell
# PowerShell
.\convert_pdfs_to_markdown.ps1 -Paths "path/to/file.pdf","path/to/directory"

# Bash
./convert_pdfs_to_markdown.sh "path/to/file.pdf" "path/to/directory"
```

## How It Works

The scripts will:

1. **Process Inputs** based on what's provided:
   - No arguments: Scan all directories in repository root
   - Specific files: Convert only those files
   - Directories: Recursively find and convert all PDFs
   - Mixed: Handle both files and directories as appropriate

2. **Skip** PDFs that already have corresponding `.md` files

3. **Choose conversion method** based on file size:
   - **Small files** (<15MB): Uses inline base64 encoding
   - **Large files** (≥15MB): Uses Google File API for upload

4. **Convert** each PDF to markdown with:
   - Proper heading structure (# ## ###)
   - Lists and formatting preserved
   - Clean, readable output

5. **Save** markdown files with the same name as the PDF (e.g., `document.pdf` → `document.md`)

## Features

- ✅ **Smart file size detection** - automatically chooses best API method
- ✅ **Duplicate prevention** - skips files that already have markdown versions
- ✅ **Rate limiting** - includes delays to avoid API limits
- ✅ **Error handling** - continues processing even if individual files fail
- ✅ **Progress feedback** - shows what's happening during conversion

## API Limits

- **Free tier**: 15 requests per minute, 1 million tokens per minute
- **File API**: Stores files for 48 hours, up to 50MB per file
- **Rate limiting**: Script includes 2-second delays between requests

## Troubleshooting

### Common Issues

1. **"API key not set"**  
   - Make sure `GOOGLE_GENAI_API_KEY` environment variable is set correctly

2. **"curl: command not found"** (Linux/macOS only)
   - Install curl: `sudo apt install curl` (Ubuntu) or `brew install curl` (macOS)

3. **API rate limit errors**
   - The script includes delays, but for many files you might need to run it multiple times
   - Consider upgrading to a paid Google Cloud plan for higher limits

4. **Large file failures**
   - Files over 20MB might need the File API method
   - Adjust the size threshold in the script if needed

### Manual Conversion

To convert a single PDF manually:

```bash
# Set file path
PDF_PATH="path/to/your/file.pdf"

# For Bash
./convert_pdfs_to_markdown.sh "path/to/your/file.pdf"

# For PowerShell
.\convert_pdfs_to_markdown.ps1 -Paths "path\to\your\file.pdf"
```

## Output Quality

Gemini 2.5 Pro is excellent at:

- Preserving document structure and hierarchy
- Converting tables to markdown format
- Maintaining lists and formatting
- Extracting text from complex layouts
- Understanding context and meaning

The markdown output should be immediately usable and well-formatted.
