## _convert: PDF/Image → Markdown Converters

Tools to convert PDFs and images to clean, well-formatted Markdown using Google Gemini 2.5 Flash. Both PowerShell and Bash variants are provided, with consistent logging and configurable thresholds.

### Contents
- `imgconversion/`
  - `convert_images_to_markdown.ps1`
  - `convert_images_to_markdown.sh`
  - `logs/` per-tool log output
- `pdfconversion/`
  - `convert_pdfs_to_markdown.ps1`
  - `convert_pdfs_to_markdown.sh`
  - `logs/` per-tool log output
- `common/`
  - `Write-Log.psm1` PowerShell logging module
  - `log.sh` Bash logging helper

### Prerequisites
- A Google Generative Language API key
  - Set `GOOGLE_GENAI_API_KEY` in your shell before running scripts.
- For Bash scripts
  - `curl`, `jq`, `base64`, `find`
  - Linux/macOS (or WSL on Windows)
- For PowerShell scripts
  - PowerShell 7+ recommended

### Environment Variables
- Required
  - `GOOGLE_GENAI_API_KEY`: your API key
- Optional logging
  - `LOG_LEVEL`: `DEBUG` (default), `INFO`, `WARN`, `ERROR`
    - Bash logs to per-tool `logs/*.log` via `common/log.sh`
    - PowerShell logs to per-tool `logs/*.log` via `common/Write-Log.psm1`
- Optional size thresholds
  - Images (Bash): `IMG_MD_MAX_INLINE_BYTES` or `IMG_MD_MAX_INLINE_MB` (default 3 MB)
  - PDFs (Bash): `PDF_MD_MAX_INLINE_BYTES` or `PDF_MD_MAX_INLINE_MB` (default 15 MB)
  - Images (PowerShell): 3 MB inline threshold
  - PDFs (PowerShell): 15 MB inline threshold

### Supported Image Formats
`.png`, `.jpg`, `.jpeg`, `.webp`, `.heic`, `.heif`

---

## Usage

### PowerShell (Windows/macOS/Linux)

Initialize environment (PowerShell):
```powershell
$env:GOOGLE_GENAI_API_KEY = 'your_api_key_here'
```

Run image conversion:
```powershell
pwsh ./imgconversion/convert_images_to_markdown.ps1 -Paths "C:\path\to\image-or-folder"
```

Run PDF conversion:
```powershell
pwsh ./pdfconversion/convert_pdfs_to_markdown.ps1 -Paths "C:\path\to\pdf-or-folder"
```

Notes
- If `-Paths` points to a directory, the script recursively processes supported files.
- A `.md` file is created next to each source file; existing `.md` files are skipped.
- Logs are written to `imgconversion/logs/*.log` and `pdfconversion/logs/*.log`.

### Bash (Linux/macOS/WSL)

Initialize environment (bash/zsh):
```bash
export GOOGLE_GENAI_API_KEY=your_api_key_here
# Optional: logging and thresholds
export LOG_LEVEL=INFO
export IMG_MD_MAX_INLINE_MB=3      # images (default 3MB)
export PDF_MD_MAX_INLINE_MB=15     # PDFs (default 15MB)
```

Run image conversion:
```bash
bash ./imgconversion/convert_images_to_markdown.sh /path/to/image-or-folder
```

Run PDF conversion:
```bash
bash ./pdfconversion/convert_pdfs_to_markdown.sh /path/to/pdf-or-folder
```

Notes
- If arguments are directories, scripts recurse to find supported files.
- Inline vs. File API is chosen by size threshold; you can override via env vars above.
- Logs are written to per-tool `logs/*.log` and are echoed to the console with colors.

---

## Logging

PowerShell
- `common/Write-Log.psm1` provides `Initialize-Logging` and `Write-Log` with levels `INFO|WARN|ERROR|DEBUG`.
- Each tool initializes logging at start and writes to its own `logs/*.log`.

Bash
- `common/log.sh` provides a `log LEVEL "message"` function.
- Set `LOG_FILE` automatically by each tool to its local `logs/*.log`; adjust if needed.

---

## Troubleshooting
- API key errors: ensure `GOOGLE_GENAI_API_KEY` is exported/set in the current shell.
- Rate limiting: scripts add a small delay between items; consider increasing if needed.
- Large files: the File API path is used automatically when size exceeds the inline threshold.


