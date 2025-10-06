#!/bin/bash

# PDF to Markdown Converter using Gemini 2.5 Flash
# Based on examples from context.md

# Accept optional paths as arguments
PATHS=("$@")

# Check if GOOGLE_GENAI_API_KEY is set
if [ -z "$GOOGLE_GENAI_API_KEY" ]; then
    log ERROR "GOOGLE_GENAI_API_KEY environment variable is not set"
    log WARN "Please set it with: export GOOGLE_GENAI_API_KEY=your_api_key_here"
    exit 1
fi

# Base URLs for Gemini API
BASE_URL="https://generativelanguage.googleapis.com/v1beta"
UPLOAD_BASE_URL="https://generativelanguage.googleapis.com/upload/v1beta"

# Common logging (console + optional file)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/log.sh"
LOG_FILE="${SCRIPT_DIR}/logs/convert_pdfs_to_markdown.log"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"

# Function to convert PDF to markdown using inline data (for smaller files)
convert_pdf_inline() {
    local pdf_path="$1"
    local output_path="$2"
    local display_name=$(basename "$pdf_path")
    display_name="${display_name%.*}"
    
    log INFO "Converting $pdf_path to markdown using inline method..."
    
    # Check for FreeBSD base64 and set flags accordingly
    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
        B64FLAGS="--input"
    else
        B64FLAGS="-w0"
    fi
    
    # Base64 encode the PDF
    ENCODED_PDF=$(base64 $B64FLAGS "$pdf_path")
    
    # Generate content using the base64 encoded PDF
    curl "${BASE_URL}/models/gemini-2.5-flash:generateContent?key=$GOOGLE_GENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
        "contents": [{
            "parts":[
            {"inline_data": {"mime_type": "application/pdf", "data": "'"$ENCODED_PDF"'"}},
            {"text": "Please convert this PDF document to clean, well-formatted markdown. Preserve all important information, structure, headings, lists, and formatting. Use appropriate markdown syntax for headings (# ## ###), lists (- or 1.), code blocks if any, and emphasis (*italic* or **bold**). Make sure the output is readable and well-organized."}
            ]
        }]
        }' 2> /dev/null > temp_response.json
    
    # Extract and save the markdown content
    if jq -e '.candidates[0].content.parts[0].text' temp_response.json > /dev/null 2>&1; then
        jq -r '.candidates[0].content.parts[0].text' temp_response.json > "$output_path"
        log INFO "Successfully converted '$pdf_path' to '$output_path'"
    else
        log ERROR "Failed to convert '$pdf_path'"
        log DEBUG "API Response: $(cat temp_response.json)"
    fi
    
    # Clean up
    rm -f temp_response.json
}

# Function to convert PDF using File API (for larger files)
convert_pdf_file_api() {
    local pdf_path="$1"
    local output_path="$2"
    local display_name=$(basename "$pdf_path")
    display_name="${display_name%.*}"
    
    log INFO "Converting $pdf_path to markdown using File API..."
    
    NUM_BYTES=$(wc -c < "$pdf_path")
    tmp_header_file=upload-header.tmp
    
    # Initial resumable request defining metadata
    curl "${UPLOAD_BASE_URL}/files?key=${GOOGLE_GENAI_API_KEY}" \
    -D upload-header.tmp \
    -H "X-Goog-Upload-Protocol: resumable" \
    -H "X-Goog-Upload-Command: start" \
    -H "X-Goog-Upload-Header-Content-Length: ${NUM_BYTES}" \
    -H "X-Goog-Upload-Header-Content-Type: application/pdf" \
    -H "Content-Type: application/json" \
    -d "{\"file\": {\"display_name\": \"${display_name}\"}}" 2> /dev/null
    
    upload_url=$(grep -i "x-goog-upload-url: " "${tmp_header_file}" | cut -d" " -f2 | tr -d "\r")
    rm "${tmp_header_file}"
    
    # Upload the actual bytes
    curl "${upload_url}" \
    -H "Content-Length: ${NUM_BYTES}" \
    -H "X-Goog-Upload-Offset: 0" \
    -H "X-Goog-Upload-Command: upload, finalize" \
    --data-binary "@${pdf_path}" 2> /dev/null > file_info.json
    
    file_uri=$(jq -r ".file.uri" file_info.json)
    log INFO "File uploaded with URI: $file_uri"
    
    # Generate content using the uploaded file
    curl "${BASE_URL}/models/gemini-2.5-flash:generateContent?key=$GOOGLE_GENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
        "contents": [{
            "parts":[
            {"text": "Please convert this PDF document to clean, well-formatted markdown. Preserve all important information, structure, headings, lists, and formatting. Use appropriate markdown syntax for headings (# ## ###), lists (- or 1.), code blocks if any, and emphasis (*italic* or **bold**). Make sure the output is readable and well-organized."},
            {"file_data":{"mime_type": "application/pdf", "file_uri": "'$file_uri'"}}]
            }]
        }' 2> /dev/null > temp_response.json
    
    # Extract and save the markdown content
    if jq -e '.candidates[0].content.parts[0].text' temp_response.json > /dev/null 2>&1; then
        jq -r '.candidates[0].content.parts[0].text' temp_response.json > "$output_path"
        log INFO "Successfully converted '$pdf_path' to '$output_path'"
    else
        log ERROR "Failed to convert '$pdf_path'"
        log DEBUG "API Response: $(cat temp_response.json)"
    fi
    
    # Clean up
    rm -f temp_response.json file_info.json
}

# Function to check if markdown file already exists
has_markdown_equivalent() {
    local pdf_path="$1"
    local md_path="${pdf_path%.pdf}.md"
    [ -f "$md_path" ]
}

# Function to get file size in bytes
get_file_size() {
    local file_path="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f%z "$file_path"
    else
        stat -c%s "$file_path"
    fi
}

# Main conversion logic
convert_pdf() {
    local pdf_path="$1"
    local md_path="${pdf_path%.pdf}.md"
    
    # Check if markdown already exists
    if has_markdown_equivalent "$pdf_path"; then
        log WARN "SKIPPING: $pdf_path - markdown file already exists"
        return
    fi
    
    # Check file size to determine method
    file_size=$(get_file_size "$pdf_path")
    # Configurable inline size threshold (default 15MB)
    if [ -n "$PDF_MD_MAX_INLINE_BYTES" ]; then
        max_inline_size="$PDF_MD_MAX_INLINE_BYTES"
    elif [ -n "$PDF_MD_MAX_INLINE_MB" ]; then
        max_inline_size=$((PDF_MD_MAX_INLINE_MB * 1024 * 1024))
    else
        max_inline_size=$((15 * 1024 * 1024))
    fi
    log DEBUG "File size: ${file_size} bytes; inline threshold: ${max_inline_size} bytes"
    
    if [ "$file_size" -lt "$max_inline_size" ]; then
        convert_pdf_inline "$pdf_path" "$md_path"
    else
        convert_pdf_file_api "$pdf_path" "$md_path"
    fi
    
    # Add a small delay to avoid rate limiting
    sleep 2
}

# Function to process a directory
process_directory() {
    local dir_path="$1"
    log INFO "Processing directory: $dir_path"
    find "$dir_path" -type f -name "*.pdf" -print0 | while IFS= read -r -d '' pdf; do
        convert_pdf "$pdf"
    done
}

# Main execution
log INFO "Finding PDF files to convert..."

if [ ${#PATHS[@]} -gt 0 ]; then
    # Process specified paths
    for path in "${PATHS[@]}"; do
        if [ -e "$path" ]; then
            if [ -d "$path" ]; then
                # If path is a directory, process all PDFs in it
                process_directory "$path"
            elif [ -f "$path" ] && [[ "$path" == *.pdf ]]; then
                # If path is a PDF file, process it
                convert_pdf "$path"
            else
                log WARN "SKIPPING: $path - not a PDF file or directory"
            fi
        else
            log ERROR "SKIPPING: $path - path does not exist"
        fi
    done
else
    # Default behavior - scan all directories in root
    log INFO "No paths specified. Scanning all directories in repository root..."
    for dir in */; do
        if [ -d "$dir" ]; then
            process_directory "${dir%/}"
        fi
    done
fi

log INFO "PDF to Markdown conversion complete!" 