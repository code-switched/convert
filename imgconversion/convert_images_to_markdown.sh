#!/bin/bash

# Image to Markdown Converter using Gemini 2.5 Flash
# Based on examples from context.md

# Accept optional paths as arguments
PATHS=("$@")

# Check if GOOGLE_GENAI_API_KEY is set
if [ -z "$GOOGLE_GENAI_API_KEY" ]; then
    log ERROR "GOOGLE_GENAI_API_KEY environment variable is not set"
    log WARN "Please set it with: export GOOGLE_GENAI_API_KEY=your_api_key_here"
    exit 1
fi

# Define supported image formats and their MIME types
# declare -A SUPPORTED_FORMATS=(
#     [".png"]="image/png"
#     [".jpg"]="image/jpeg"
#     [".jpeg"]="image/jpeg"
#     [".webp"]="image/webp"
#     [".heic"]="image/heic"
#     [".heif"]="image/heif"
# )

# Base URLs for Gemini API
BASE_URL="https://generativelanguage.googleapis.com/v1beta"
UPLOAD_BASE_URL="https://generativelanguage.googleapis.com/upload/v1beta"

# Common logging (console + optional file)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/log.sh"
LOG_FILE="${SCRIPT_DIR}/logs/convert_images_to_markdown.log"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"

# Function to convert Image to markdown using inline data (for smaller files)
convert_image_inline() {
    local image_path="$1"
    local output_path="$2"
    local display_name=$(basename "$image_path")
    display_name="${display_name%.*}"
    
    log INFO "Converting $image_path to markdown using inline method..."
    
    # Check for FreeBSD base64 and set flags accordingly
    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
        B64FLAGS="--input"
    else
        B64FLAGS="-w0"
    fi
    
    # Base64 encode the Image
    ENCODED_IMAGE=$(base64 $B64FLAGS "$image_path")
    
    # Generate content using the base64 encoded image
    curl "${BASE_URL}/models/gemini-2.5-flash:generateContent?key=$GOOGLE_GENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
        "contents": [{
            "parts":[
            {"inline_data": {"mime_type": "'$(get_mime_type "$image_path")'", "data": "'"$ENCODED_IMAGE"'"}},
            {"text": "Please convert this image to clean, well-formatted markdown. If the image contains text, transcribe it accurately. If it contains structured information like lists, tables, or code, preserve the structure. For diagrams or user interfaces, describe them in detail. Ensure the final markdown is readable and well-organized."}
            ]
        }]
        }' 2> /dev/null > temp_response.json
    
    # Extract the markdown content and save to file
    if jq -e '.candidates[0].content.parts[0].text' temp_response.json > /dev/null 2>&1; then
        jq -r '.candidates[0].content.parts[0].text' temp_response.json > "$output_path"
        log INFO "Successfully converted '$image_path' to '$output_path'"
    else
        log ERROR "Failed to convert '$image_path'"
        log DEBUG "API Response: $(cat temp_response.json)"
    fi
    
    # Clean up
    rm -f temp_response.json
}

# Function to convert Image using File API (for larger files)
convert_image_file_api() {
    local image_path="$1"
    local output_path="$2"
    local display_name=$(basename "$image_path")
    display_name="${display_name%.*}"
    
    log INFO "Converting $image_path to markdown using File API..."
    
    NUM_BYTES=$(wc -c < "$image_path")
    tmp_header_file=upload-header.tmp
    
    # Initial resumable request defining metadata
    curl "${UPLOAD_BASE_URL}/files?key=${GOOGLE_GENAI_API_KEY}" \
    -D upload-header.tmp \
    -H "X-Goog-Upload-Protocol: resumable" \
    -H "X-Goog-Upload-Command: start" \
    -H "X-Goog-Upload-Header-Content-Length: ${NUM_BYTES}" \
    -H "X-Goog-Upload-Header-Content-Type: $(get_mime_type "$image_path")" \
    -H "Content-Type: application/json" \
    -d "{\"file\": {\"display_name\": \"${display_name}\"}}" 2> /dev/null
    
    upload_url=$(grep -i "x-goog-upload-url: " "${tmp_header_file}" | cut -d" " -f2 | tr -d "\r")
    rm "${tmp_header_file}"
    
    # Upload the actual bytes
    curl "${upload_url}" \
    -H "Content-Length: ${NUM_BYTES}" \
    -H "X-Goog-Upload-Offset: 0" \
    -H "X-Goog-Upload-Command: upload, finalize" \
    --data-binary "@${image_path}" 2> /dev/null > file_info.json
    
    file_uri=$(jq -r ".file.uri" file_info.json)
    log INFO "File uploaded with URI: $file_uri"
    
    # Generate content using that file
    curl "${BASE_URL}/models/gemini-2.5-flash:generateContent?key=$GOOGLE_GENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
        "contents": [{
            "parts":[
            {"text": "Please convert this image to clean, well-formatted markdown. If the image contains text, transcribe it accurately. If it contains structured information like lists, tables, or code, preserve the structure. For diagrams or user interfaces, describe them in detail. Ensure the final markdown is readable and well-organized."},
            {"file_data":{"mime_type": "'$(get_mime_type "$image_path")'", "file_uri": "'$file_uri'"}}]
            }]
        }' 2> /dev/null > temp_response.json
    
    # Extract the markdown content and save to file
    if jq -e '.candidates[0].content.parts[0].text' temp_response.json > /dev/null 2>&1; then
        jq -r '.candidates[0].content.parts[0].text' temp_response.json > "$output_path"
        log INFO "Successfully converted '$image_path' to '$output_path'"
    else
        log ERROR "Failed to convert '$image_path'"
        log DEBUG "API Response: $(cat temp_response.json)"
    fi
    
    # Clean up
    rm -f temp_response.json file_info.json
}

# Function to check if markdown file already exists
has_markdown_equivalent() {
    local image_path="$1"
    local md_path="${image_path%.*}.md"
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

# Function to get file extension (in lowercase)
get_extension() {
    local filename="$1"
    echo "${filename##*.}" | tr '[:upper:]' '[:lower:]'
}

# Function to get mime type for file
get_mime_type() {
    local file_path="$1"
    local ext=".$(get_extension "$file_path")"
    case "$ext" in
        ".png") echo "image/png" ;;
        ".jpg"|".jpeg") echo "image/jpeg" ;;
        ".webp") echo "image/webp" ;;
        ".heic") echo "image/heic" ;;
        ".heif") echo "image/heif" ;;
        *) echo "" ;; # Unsupported format
    esac
}

# Main conversion logic
convert_image() {
    local image_path="$1"
    local md_path="${image_path%.*}.md"
    
    # Check if markdown already exists
    if has_markdown_equivalent "$image_path"; then
        log WARN "SKIPPING: $image_path - markdown file already exists"
        return
    fi
    
    # Check file size to determine method
    file_size=$(get_file_size "$image_path")
    if [ -n "$IMG_MD_MAX_INLINE_BYTES" ]; then
        max_inline_size="$IMG_MD_MAX_INLINE_BYTES"
    elif [ -n "$IMG_MD_MAX_INLINE_MB" ]; then
        max_inline_size=$((IMG_MD_MAX_INLINE_MB * 1024 * 1024))
    else
        max_inline_size=$((3 * 1024 * 1024))
    fi
    log DEBUG "File size: ${file_size} bytes; inline threshold: ${max_inline_size} bytes"
    
    if [ "$file_size" -lt "$max_inline_size" ]; then
        convert_image_inline "$image_path" "$md_path"
    else
        convert_image_file_api "$image_path" "$md_path"
    fi
    
    # Add a small delay to avoid rate limiting
    sleep 2
}

# Function to process a directory
process_directory() {
    local dir_path="$1"
    log INFO "Processing directory: $dir_path"
    
    # Create pattern for find command from supported extensions
    local pattern=""
    local supported_extensions=("png" "jpg" "jpeg" "webp" "heic" "heif")
    for ext in "${supported_extensions[@]}"; do
        [ -z "$pattern" ] && pattern="-name *.${ext}" || pattern="$pattern -o -name *.${ext}"
    done
    
    find "$dir_path" -type f \( $pattern \) -print0 | while IFS= read -r -d '' img; do
        convert_image "$img"
    done
}

# Main execution
log INFO "Finding image files to convert..."

if [ ${#PATHS[@]} -gt 0 ]; then
    # Process specified paths
    for path in "${PATHS[@]}"; do
        if [ -e "$path" ]; then
            if [ -d "$path" ]; then
                # If path is a directory, process all PNGs in it
                process_directory "$path"
            elif [ -f "$path" ]; then
                # Check if the file has a supported extension
                if [ -n "$(get_mime_type "$path")" ]; then
                    # If path is a supported image file, process it
                    convert_image "$path"
                else
                    log WARN "SKIPPING: $path - not a supported image file. Supported formats: png, jpg, jpeg, webp, heic, heif"
                fi
            else
                log WARN "SKIPPING: $path - not a supported image file or directory"
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

log INFO "Image to Markdown conversion complete!"
