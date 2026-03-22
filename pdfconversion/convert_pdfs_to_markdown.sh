#!/bin/bash

# PDF to Markdown Converter using Gemini 2.5 Flash
# Based on examples from context.md

# Common logging (console + optional file)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/log.sh"
LOG_FILE="${SCRIPT_DIR}/logs/convert_pdfs_to_markdown.log"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"

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
MODEL_NAME="${PDF_MD_MODEL_NAME:-gemini-2.5-flash}"
GEMINI_PDF_MAX_BYTES=$((50 * 1024 * 1024))
FILE_API_POLL_INTERVAL_SECONDS="${PDF_MD_FILE_API_POLL_INTERVAL_SECONDS:-${FILE_API_POLL_INTERVAL_SECONDS:-2}}"
FILE_API_MAX_POLL_ATTEMPTS="${PDF_MD_FILE_API_MAX_POLL_ATTEMPTS:-${FILE_API_MAX_POLL_ATTEMPTS:-90}}"
PDF_CONVERSION_PROMPT="Please convert this PDF document to clean, well-formatted markdown. Preserve all important information, structure, headings, lists, and formatting. Use appropriate markdown syntax for headings (# ## ###), lists (- or 1.), code blocks if any, and emphasis (*italic* or **bold**). Make sure the output is readable and well-organized."

wait_for_uploaded_file_active() {
    local file_name="$1"
    local metadata_path="$2"
    local attempt=0
    local state error_message

    while true; do
        state=$(jq -r '.file.state // "STATE_UNSPECIFIED"' "$metadata_path")

        case "$state" in
            ACTIVE)
                return 0
                ;;
            FAILED)
                error_message=$(jq -c '.file.error // {}' "$metadata_path")
                log ERROR "Uploaded file processing failed for '${file_name}': ${error_message}"
                return 1
                ;;
            PROCESSING|STATE_UNSPECIFIED|"")
                if [ "$attempt" -ge "$FILE_API_MAX_POLL_ATTEMPTS" ]; then
                    log ERROR "Timed out waiting for uploaded file '${file_name}' to become ACTIVE"
                    return 1
                fi

                attempt=$((attempt + 1))
                log INFO "Waiting for uploaded file to become ACTIVE (attempt ${attempt}/${FILE_API_MAX_POLL_ATTEMPTS})..."
                sleep "$FILE_API_POLL_INTERVAL_SECONDS"

                if ! curl -fsS "${BASE_URL}/${file_name}?key=${GOOGLE_GENAI_API_KEY}" \
                    -H 'Content-Type: application/json' \
                    > "$metadata_path"; then
                    log ERROR "Failed to fetch status for uploaded file '${file_name}'"
                    return 1
                fi
                ;;
            *)
                log WARN "Uploaded file '${file_name}' returned unexpected state '${state}'"
                return 1
                ;;
        esac
    done
}

# Function to convert PDF to markdown using inline data (for smaller files)
convert_pdf_inline() {
    local pdf_path="$1"
    local output_path="$2"
    local display_name=$(basename "$pdf_path")
    display_name="${display_name%.*}"
    local payload_file
    payload_file=$(mktemp "${SCRIPT_DIR}/payload.XXXXXX.json")
    
    log INFO "Converting $pdf_path to markdown using inline method..."
    
    # Build the inline JSON payload without hitting shell argument limits
    local base64_cmd newline_filter
    if base64 --help 2>&1 | grep -q "\-w, --wrap"; then
        base64_cmd=(base64 -w0 "$pdf_path")
        newline_filter=(cat)
    elif [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
        base64_cmd=(base64 --input "$pdf_path")
        newline_filter=(tr -d '\n')
    else
        base64_cmd=(base64 "$pdf_path")
        newline_filter=(tr -d '\n')
    fi
    
    if ! "${base64_cmd[@]}" | "${newline_filter[@]}" \
        | jq -Rs --arg prompt "$PDF_CONVERSION_PROMPT" '{
            contents: [{
                parts: [
                    { inline_data: { mime_type: "application/pdf", data: . } },
                    { text: $prompt }
                ]
            }]
        }' > "$payload_file"; then
        log ERROR "Failed to build inline payload for $pdf_path"
        rm -f "$payload_file"
        return
    fi
    
    # Generate content using the base64 encoded PDF
    curl "${BASE_URL}/models/${MODEL_NAME}:generateContent?key=$GOOGLE_GENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        --data-binary @"$payload_file" \
        2> /dev/null > temp_response.json
    
    # Extract and save the markdown content
    if jq -e '.candidates[0].content.parts[0].text' temp_response.json > /dev/null 2>&1; then
        jq -r '.candidates[0].content.parts[0].text' temp_response.json > "$output_path"
        log INFO "Successfully converted '$pdf_path' to '$output_path'"
        rm -f temp_response.json "$payload_file"
        return 0
    else
        log ERROR "Failed to convert '$pdf_path'"
        log DEBUG "API Response: $(cat temp_response.json)"
        rm -f temp_response.json "$payload_file"
        return 1
    fi
}

# Function to convert PDF using File API (for larger files)
convert_pdf_file_api() {
    local pdf_path="$1"
    local output_path="$2"
    local display_name=$(basename "$pdf_path")
    display_name="${display_name%.*}"
    local num_bytes tmp_header_file file_info_file payload_file upload_url file_name file_uri file_state upload_metadata
    
    log INFO "Converting $pdf_path to markdown using File API..."
    
    num_bytes=$(get_file_size "$pdf_path")

    if [ "$num_bytes" -gt "$GEMINI_PDF_MAX_BYTES" ]; then
        log ERROR "Skipping '$pdf_path': Gemini PDF support is limited to 50 MB per document; file is ${num_bytes} bytes"
        return 1
    fi

    tmp_header_file=$(mktemp "${SCRIPT_DIR}/upload-header.XXXXXX.tmp")
    file_info_file=$(mktemp "${SCRIPT_DIR}/file-info.XXXXXX.json")
    payload_file=$(mktemp "${SCRIPT_DIR}/payload.XXXXXX.json")
    upload_metadata=$(jq -nc --arg display_name "$display_name" '{file: {display_name: $display_name}}')
    
    # Initial resumable request defining metadata
    if ! curl -fsS "${UPLOAD_BASE_URL}/files?key=${GOOGLE_GENAI_API_KEY}" \
        -D "$tmp_header_file" \
        -H "X-Goog-Upload-Protocol: resumable" \
        -H "X-Goog-Upload-Command: start" \
        -H "X-Goog-Upload-Header-Content-Length: ${num_bytes}" \
        -H "X-Goog-Upload-Header-Content-Type: application/pdf" \
        -H "Content-Type: application/json" \
        --data-binary "$upload_metadata" \
        > /dev/null; then
        log ERROR "Failed to start File API upload for '$pdf_path'"
        rm -f "$tmp_header_file" "$file_info_file" "$payload_file"
        return 1
    fi
    
    upload_url=$(grep -i "x-goog-upload-url: " "${tmp_header_file}" | cut -d" " -f2 | tr -d "\r")
    rm -f "${tmp_header_file}"

    if [ -z "$upload_url" ]; then
        log ERROR "Failed to obtain resumable upload URL for '$pdf_path'"
        rm -f "$file_info_file" "$payload_file"
        return 1
    fi
    
    # Upload the actual bytes
    if ! curl -fsS "${upload_url}" \
        -H "Content-Length: ${num_bytes}" \
        -H "X-Goog-Upload-Offset: 0" \
        -H "X-Goog-Upload-Command: upload, finalize" \
        --data-binary "@${pdf_path}" \
        > "$file_info_file"; then
        log ERROR "Failed to upload '$pdf_path' with File API"
        rm -f "$file_info_file" "$payload_file"
        return 1
    fi
    
    file_name=$(jq -r '.file.name // empty' "$file_info_file")
    file_uri=$(jq -r '.file.uri // empty' "$file_info_file")

    if [ -z "$file_name" ] || [ -z "$file_uri" ]; then
        log ERROR "File API upload for '$pdf_path' did not return the expected file metadata"
        log DEBUG "Upload response: $(cat "$file_info_file")"
        rm -f "$file_info_file" "$payload_file"
        return 1
    fi

    log INFO "File uploaded with URI: $file_uri"

    file_state=$(jq -r '.file.state // empty' "$file_info_file")
    if [ "$file_state" != "ACTIVE" ]; then
        if ! wait_for_uploaded_file_active "$file_name" "$file_info_file"; then
            log DEBUG "Latest file metadata: $(cat "$file_info_file")"
            rm -f "$file_info_file" "$payload_file"
            return 1
        fi
    fi

    file_uri=$(jq -r '.file.uri // empty' "$file_info_file")
    if [ -z "$file_uri" ]; then
        log ERROR "Uploaded file '${file_name}' became ACTIVE without a usable URI"
        log DEBUG "Latest file metadata: $(cat "$file_info_file")"
        rm -f "$file_info_file" "$payload_file"
        return 1
    fi
    
    # Generate content using the uploaded file
    if ! jq -n \
        --arg prompt "$PDF_CONVERSION_PROMPT" \
        --arg file_uri "$file_uri" \
        '{
            contents: [{
                parts: [
                    { text: $prompt },
                    { file_data: { mime_type: "application/pdf", file_uri: $file_uri } }
                ]
            }]
        }' > "$payload_file"; then
        log ERROR "Failed to build File API prompt payload for '$pdf_path'"
        rm -f "$file_info_file" "$payload_file"
        return 1
    fi

    curl "${BASE_URL}/models/${MODEL_NAME}:generateContent?key=$GOOGLE_GENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        --data-binary @"$payload_file" \
        2> /dev/null > temp_response.json
    
    # Extract and save the markdown content
    if jq -e '.candidates[0].content.parts[0].text' temp_response.json > /dev/null 2>&1; then
        jq -r '.candidates[0].content.parts[0].text' temp_response.json > "$output_path"
        log INFO "Successfully converted '$pdf_path' to '$output_path'"
        rm -f temp_response.json "$file_info_file" "$payload_file"
        return 0
    else
        log ERROR "Failed to convert '$pdf_path'"
        log DEBUG "API Response: $(cat temp_response.json)"
        rm -f temp_response.json "$file_info_file" "$payload_file"
        return 1
    fi
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
    local file_size max_inline_size conversion_status
    
    # Check if markdown already exists
    if has_markdown_equivalent "$pdf_path"; then
        log WARN "SKIPPING: $pdf_path - markdown file already exists"
        return 0
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

    if [ "$file_size" -gt "$GEMINI_PDF_MAX_BYTES" ]; then
        log ERROR "Skipping '$pdf_path': Gemini PDF support is limited to 50 MB per document; split or compress this PDF before conversion"
        conversion_status=1
    elif [ "$file_size" -lt "$max_inline_size" ]; then
        convert_pdf_inline "$pdf_path" "$md_path"
        conversion_status=$?
    else
        convert_pdf_file_api "$pdf_path" "$md_path"
        conversion_status=$?
    fi
    
    # Add a small delay to avoid rate limiting
    sleep 2
    return "$conversion_status"
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
