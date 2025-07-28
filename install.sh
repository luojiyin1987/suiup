#!/bin/sh
set -e

# Configuration
GITHUB_REPO="MystenLabs/suiup"
RELEASES_URL="https://github.com/${GITHUB_REPO}/releases"

# Set up colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

printf '%bsuiup installer script%b\n' "${CYAN}" "${NC}"
printf 'This script will install the suiup binary to your system.\n'

# Get latest version from GitHub
get_latest_version() {
    # Check if GITHUB_TOKEN is set and use it for authentication
    auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: Bearer $GITHUB_TOKEN"
    fi

    if command -v curl >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            curl -fsSL -H "$auth_header" "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/'
        else
            curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/'
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            wget --quiet --header="$auth_header" -O- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/'
        else
            wget --quiet -O- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/'
        fi
    else
        printf '%bError: Neither curl nor wget is available. Please install one of them.%b\n' "${RED}" "${NC}"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux" ;;
        Darwin*)    echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)          echo "unknown" ;;
    esac
}

# Get the appropriate download URL
get_download_url() {
    os=$1
    arch=$2
    version=$3
    
    # Construct the filename based on OS and architecture
    if [ "$os" = "macos" ]; then
        echo "${RELEASES_URL}/download/${version}/suiup-macOS-${arch}.tar.gz"
    elif [ "$os" = "linux" ]; then
        echo "${RELEASES_URL}/download/${version}/suiup-Linux-musl-${arch}.tar.gz"
    elif [ "$os" = "windows" ]; then
        # Based on GitHub releases, Windows only has ARM64 version available
        echo "${RELEASES_URL}/download/${version}/suiup-Windows-msvc-${arch}.zip"
    else
        echo ""
    fi
}

# Determine installation directory
get_install_dir() {
    os=$1
    
    if [ "$os" = "macos" ] || [ "$os" = "linux" ]; then
        # Use ~/.local/bin on Unix-like systems if it exists or can be created
        local_bin="$HOME/.local/bin"
        if [ -d "$local_bin" ] || mkdir -p "$local_bin" 2>/dev/null; then
            echo "$local_bin"
        else
            # Fallback to /usr/local/bin if we can write to it
            if [ -w "/usr/local/bin" ]; then
                echo "/usr/local/bin"
            else
                # Last resort, use a directory in home
                mkdir -p "$HOME/bin"
                echo "$HOME/bin"
            fi
        fi
    elif [ "$os" = "windows" ]; then
        # On Windows, use %USERPROFILE%\.local\bin
        win_dir="$HOME/.local/bin"
        mkdir -p "$win_dir"
        echo "$win_dir"
    else
        echo "$HOME/bin"
        mkdir -p "$HOME/bin"
    fi
}

# Check if the directory is in PATH
check_path() {
    dir=$1
    os=$2
    
    # Different path separators for different OSes
    separator=":"
    if [ "$os" = "windows" ]; then
        separator=";"
    fi
    
    # POSIX-compliant way to check if directory is in PATH
    case ":$PATH:" in
        *":$dir:"*) 
            printf '%b%s is already in your PATH%b\n' "${GREEN}" "$dir" "${NC}"
            ;;
        *)
            printf '%bWarning: %s is not in your PATH%b\n' "${YELLOW}" "$dir" "${NC}"
            
            # Provide instructions based on OS
            if [ "$os" = "macos" ] || [ "$os" = "linux" ]; then
                printf 'Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):\n'
                printf "%bexport PATH=\"%s:\$PATH\"%b\n" "${GREEN}" "$dir" "${NC}"
            elif [ "$os" = "windows" ]; then
                printf 'Add this directory to your PATH by running this in PowerShell:\n'
                printf "%b\$env:Path += \"%s%s\"%b\n" "${GREEN}" "$separator" "$dir" "${NC}"
                printf 'To make it permanent, add it through Windows System Properties:\n'
                printf 'Control Panel → System → Advanced system settings → Environment Variables\n'
            fi
            ;;
    esac
}

# Download a file with curl or wget
download_file() {
    url=$1
    output_file=$2
    
    printf 'Downloading %s to %s...\n' "$url" "$output_file"
    
    # Check if GITHUB_TOKEN is set and use it for authentication
    auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: Bearer $GITHUB_TOKEN"
    fi

    if command -v curl >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            curl -fsSL -H "$auth_header" "$url" -o "$output_file"
        else
            curl -fsSL "$url" -o "$output_file"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            wget --quiet --header="$auth_header" "$url" -O "$output_file"
        else
            wget --quiet "$url" -O "$output_file"
        fi
    else
        printf '%bError: Neither curl nor wget is available. Please install one of them.%b\n' "${RED}" "${NC}"
        exit 1
    fi
}

# Detect available hash calculation tool
detect_hash_tool() {
    # Check for sha256sum (Linux, some macOS with coreutils)
    if command -v sha256sum >/dev/null 2>&1; then
        echo "sha256sum"
    # Check for shasum (macOS default)
    elif command -v shasum >/dev/null 2>&1; then
        echo "shasum"
    # Check for PowerShell Get-FileHash (Windows)
    elif command -v powershell.exe >/dev/null 2>&1; then
        echo "powershell"
    # Check for certutil (Windows fallback)
    elif command -v certutil >/dev/null 2>&1; then
        echo "certutil"
    else
        echo ""
    fi
}

# Calculate SHA256 hash of a file
calculate_hash() {
    file_path=$1
    hash_tool=$(detect_hash_tool)
    
    case "$hash_tool" in
        "sha256sum")
            sha256sum "$file_path" | cut -d' ' -f1
            ;;
        "shasum")
            shasum -a 256 "$file_path" | cut -d' ' -f1
            ;;
        "powershell")
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -Path '$file_path' -Algorithm SHA256).Hash.ToLower()"
            ;;
        "certutil")
            # certutil outputs in a specific format, we need to extract the hash
            certutil -hashfile "$file_path" SHA256 | grep -v "hash" | grep -v "CertUtil" | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]'
            ;;
        *)
            printf '%bWarning: No suitable hash calculation tool found. Skipping integrity check.%b\n' "${YELLOW}" "${NC}"
            echo ""
            ;;
    esac
}

# Get the checksum download URL
get_checksum_url() {
    os=$1
    arch=$2
    version=$3
    
    # Construct the checksum filename based on OS and architecture (matching GitHub releases format)
    if [ "$os" = "macos" ]; then
        echo "${RELEASES_URL}/download/${version}/suiup-macOS-${arch}.tar.gz.sha256"
    elif [ "$os" = "linux" ]; then
        echo "${RELEASES_URL}/download/${version}/suiup-Linux-musl-${arch}.tar.gz.sha256"
    elif [ "$os" = "windows" ]; then
        echo "${RELEASES_URL}/download/${version}/suiup-Windows-msvc-${arch}.zip.sha256"
    else
        echo ""
    fi
}

# Download checksum file
download_checksum() {
    checksum_url=$1
    checksum_file=$2
    
    printf 'Downloading checksum file...\n'
    
    # Check if GITHUB_TOKEN is set and use it for authentication
    auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: Bearer $GITHUB_TOKEN"
    fi

    if command -v curl >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            if curl -fsSL -H "$auth_header" "$checksum_url" -o "$checksum_file" 2>/dev/null; then
                return 0
            else
                return 1
            fi
        else
            if curl -fsSL "$checksum_url" -o "$checksum_file" 2>/dev/null; then
                return 0
            else
                return 1
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            if wget --quiet --header="$auth_header" "$checksum_url" -O "$checksum_file" 2>/dev/null; then
                return 0
            else
                return 1
            fi
        else
            if wget --quiet "$checksum_url" -O "$checksum_file" 2>/dev/null; then
                return 0
            else
                return 1
            fi
        fi
    else
        return 1
    fi
}

# Parse checksum from various common checksum file formats
parse_checksum_file() {
    checksum_file=$1
    target_filename=$2  # Optional: for format validation
    
    if [ ! -s "$checksum_file" ]; then
        echo ""
        return 1
    fi
    
    # Read the checksum file content
    content=$(cat "$checksum_file")
    expected_hash=""
    
    # Try different parsing strategies, prioritizing more specific formats
    
    # Strategy 1: Look for lines containing the target filename (most reliable)
    if [ -n "$target_filename" ]; then
        # Extract basename for comparison
        base_filename=$(basename "$target_filename")
        line_with_file=$(echo "$content" | grep -i "$base_filename" | head -n 1)
        
        if [ -n "$line_with_file" ]; then
            # Try hash + whitespace + filename format
            expected_hash=$(echo "$line_with_file" | sed -n 's/^\([a-fA-F0-9]\{64\}\)[[:space:]]\+.*$/\1/p' | tr '[:upper:]' '[:lower:]')
            
            # Try filename + whitespace + hash format (some tools use this)
            if [ -z "$expected_hash" ]; then
                expected_hash=$(echo "$line_with_file" | sed -n 's/^.*[[:space:]]\+\([a-fA-F0-9]\{64\}\)$/\1/p' | tr '[:upper:]' '[:lower:]')
            fi
        fi
    fi
    
    # Strategy 2: If no filename match, try first line with 64-char hex string
    if [ -z "$expected_hash" ]; then
        # Look for a line that starts with a 64-character hex string
        expected_hash=$(echo "$content" | sed -n 's/^\([a-fA-F0-9]\{64\}\).*$/\1/p' | head -n 1 | tr '[:upper:]' '[:lower:]')
    fi
    
    # Strategy 3: Look for any 64-character hex string anywhere in the file
    if [ -z "$expected_hash" ]; then
        expected_hash=$(echo "$content" | grep -o '[a-fA-F0-9]\{64\}' | head -n 1 | tr '[:upper:]' '[:lower:]')
    fi
    
    # Strategy 4: Handle common hash tools output formats
    if [ -z "$expected_hash" ]; then
        # shasum/sha256sum format: "hash  filename" or "hash *filename"
        expected_hash=$(echo "$content" | sed -n 's/^\([a-fA-F0-9]\{64\}\)[[:space:]]\+[\*[:space:]]*.*$/\1/p' | head -n 1 | tr '[:upper:]' '[:lower:]')
    fi
    
    # Validate the extracted hash
    if [ -n "$expected_hash" ] && [ ${#expected_hash} -eq 64 ]; then
        echo "$expected_hash"
        return 0
    else
        echo ""
        return 1
    fi
}

# Verify file integrity using checksum
verify_file_integrity() {
    binary_file=$1
    checksum_file=$2
    
    # Check if we have a hash calculation tool
    hash_tool=$(detect_hash_tool)
    if [ -z "$hash_tool" ]; then
        printf '%bWarning: Cannot verify file integrity - no hash calculation tool available%b\n' "${YELLOW}" "${NC}"
        return 0  # Continue installation but with warning
    fi
    
    # Check if checksum file exists
    if [ ! -f "$checksum_file" ]; then
        printf '%bWarning: Checksum file not found. Skipping integrity verification.%b\n' "${YELLOW}" "${NC}"
        return 0  # Continue installation but with warning
    fi
    
    printf 'Verifying file integrity...\n'
    
    # Calculate actual hash
    actual_hash=$(calculate_hash "$binary_file")
    if [ -z "$actual_hash" ]; then
        printf '%bWarning: Failed to calculate file hash. Skipping integrity verification.%b\n' "${YELLOW}" "${NC}"
        return 0
    fi
    
    # Parse expected hash from checksum file using flexible parsing
    expected_hash=$(parse_checksum_file "$checksum_file" "$binary_file")
    
    if [ -z "$expected_hash" ]; then
        printf '%bWarning: Could not parse checksum file. File contents:%b\n' "${YELLOW}" "${NC}"
        printf '%s\n' "--- Checksum file content ---"
        cat "$checksum_file" | head -5  # Show first 5 lines for debugging
        printf '%s\n' "--- End of checksum file ---"
        printf 'Skipping integrity verification.\n'
        return 0
    fi
    
    # Compare hashes
    if [ "$actual_hash" = "$expected_hash" ]; then
        printf '%bFile integrity verified successfully ✓%b\n' "${GREEN}" "${NC}"
        return 0
    else
        printf '%bError: File integrity check failed!%b\n' "${RED}" "${NC}"
        printf 'Expected: %s\n' "$expected_hash"
        printf 'Actual:   %s\n' "$actual_hash"
        printf 'The downloaded file may be corrupted or tampered with.\n'
        printf '\nChecksum file content:\n'
        cat "$checksum_file"
        return 1
    fi
}

# Check for existing binaries that might conflict
check_existing_binaries() {
    local install_dir=$1
    local os=$2
    local found_binaries=""
    local binary

    # List of binaries to check
    for binary in sui mvr walrus; do
        # Check if binary exists in PATH
        if command -v "$binary" >/dev/null 2>&1; then
            # Get the full path of the existing binary
            existing_path=$(command -v "$binary")
            # Only warn if it's not in our installation directory
            if [ "$existing_path" != "$install_dir/$binary" ]; then
                if [ -n "$found_binaries" ]; then
                    found_binaries="$found_binaries, $binary"
                else
                    found_binaries="$binary"
                fi
            fi
        fi
    done

    if [ -n "$found_binaries" ]; then
        printf '\n%bWarning: The following binaries are already installed on your system:%b\n' "${YELLOW}" "${NC}"
        printf '  %s\n' "$found_binaries"
        printf '\n%s\n' "This might cause conflicts with suiup-installed tools."
        printf '%s\n' "You have two options:"
        printf '1. Uninstall the existing binaries\n'
        printf '2. Ensure %s is listed BEFORE other directories in your PATH\n' "$install_dir"
        
        if [ "$os" = "macos" ] || [ "$os" = "linux" ]; then
            printf '\nTo check your current PATH order, run:\n'
            printf '%becho $PATH | tr ":" "\\n" | nl%b\n' "${CYAN}" "${NC}"
            printf '\nTo modify your PATH order, edit your shell profile (~/.bashrc, ~/.zshrc, etc.)\n'
            printf 'and ensure this line appears BEFORE any other PATH modifications:\n'
            printf '%bexport PATH="%s:$PATH"%b\n' "${GREEN}" "$install_dir" "${NC}"
        elif [ "$os" = "windows" ]; then
            printf '\nTo check your current PATH order in PowerShell, run:\n'
            printf '%b$env:Path -split ";" | ForEach-Object { $i++; Write-Host "$i. $_" }%b\n' "${CYAN}" "${NC}"
            printf '\nTo modify your PATH order:\n'
            printf '1. Open System Properties (Win + Pause/Break)\n'
            printf '2. Click "Environment Variables"\n'
            printf '3. Under "User variables", find and select "Path"\n'
            printf '4. Click "Edit" and move %s to the top of the list\n' "$install_dir"
        fi
    fi
}

# Main installation function
install_suiup() {
    os=$(detect_os)
    arch=$(detect_arch)
    version=$(get_latest_version)
    
    if [ -z "$version" ]; then
        printf '%bError: Could not fetch latest version%b\n' "${RED}" "${NC}"
        exit 1
    fi
    
    # Special handling for Windows x86_64 (not currently available in releases)
    if [ "$os" = "windows" ] && [ "$arch" = "x86_64" ]; then
        printf '%bWarning: Windows x86_64 is not currently available. Only ARM64 is supported.%b\n' "${YELLOW}" "${NC}"
        printf 'Available Windows architecture: arm64\n'
        printf 'If you are running on ARM64 Windows, the script will continue...\n'
        # Override architecture for Windows
        arch="arm64"
    fi
    
    download_url=$(get_download_url "$os" "$arch" "$version")
    
    if [ -z "$download_url" ]; then
        printf '%bError: Unsupported OS or architecture: %s/%s%b\n' "${RED}" "$os" "$arch" "${NC}"
        exit 1
    fi
    
    printf 'Detected OS: %s\n' "$os"
    printf 'Detected architecture: %s\n' "$arch"
    printf 'Latest version: %s\n' "$version"
    printf 'Download URL: %s\n' "$download_url"
    
    # Create temporary directory
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    
    # Download the binary
    if [ "$os" = "windows" ]; then
        binary_file="$tmp_dir/suiup.zip"
        checksum_file="$tmp_dir/suiup.zip.sha256"
    else
        binary_file="$tmp_dir/suiup.tar.gz"
        checksum_file="$tmp_dir/suiup.tar.gz.sha256"
    fi
    
    download_file "$download_url" "$binary_file"
    
    # Download and verify checksum file (unless skipped)
    checksum_url=$(get_checksum_url "$os" "$arch" "$version")
    
    if [ -z "$checksum_url" ]; then
        printf '%bWarning: No checksum URL available for this version. Skipping integrity check.%b\n' "${YELLOW}" "${NC}"
    else
        if ! download_checksum "$checksum_url" "$checksum_file"; then
            printf '%bWarning: Failed to download checksum file. Skipping integrity check.%b\n' "${YELLOW}" "${NC}"
        else
            if ! verify_file_integrity "$binary_file" "$checksum_file"; then
                printf '%bError: File integrity check failed. Aborting installation.%b\n' "${RED}" "${NC}"
                exit 1
            fi
        fi
    fi
    
    # Extract the binary
    printf 'Extracting binary...\n'
    if [ "$os" = "windows" ]; then
        # Windows binary is in zip format
        if command -v unzip >/dev/null 2>&1; then
            unzip -q "$binary_file" -d "$tmp_dir"
            source_binary="$tmp_dir/suiup.exe"
        elif command -v powershell.exe >/dev/null 2>&1; then
            # Use PowerShell Expand-Archive as fallback
            printf 'Using PowerShell to extract zip file...\n'
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '$binary_file' -DestinationPath '$tmp_dir' -Force"
            source_binary="$tmp_dir/suiup.exe"
        else
            printf '%bError: No zip extraction tool found!%b\n' "${RED}" "${NC}"
            printf 'To extract Windows binaries, you need one of the following:\n\n'
            printf '%b1. Install unzip:%b\n' "${CYAN}" "${NC}"
            printf '   - On WSL/MSYS2/Cygwin: sudo apt-get install unzip (or equivalent)\n'
            printf '   - On Windows with Chocolatey: choco install unzip\n'
            printf '   - On Windows with Scoop: scoop install unzip\n'
            printf '   - Download from: http://gnuwin32.sourceforge.net/packages/unzip.htm\n\n'
            printf '%b2. Use PowerShell (recommended):%b\n' "${CYAN}" "${NC}"
            printf '   PowerShell should be available on all modern Windows systems.\n'
            printf '   If PowerShell is not available, please install it from:\n'
            printf '   https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell\n\n'
            printf '%b3. Manual extraction:%b\n' "${CYAN}" "${NC}"
            printf '   - Download the zip file manually from: %s\n' "$download_url"
            printf '   - Extract suiup.exe using Windows built-in zip support\n'
            printf '   - Place suiup.exe in a directory that is in your PATH\n'
            exit 1
        fi
    else
        tar -xzf "$binary_file" -C "$tmp_dir"
        source_binary="$tmp_dir/suiup"
    fi
    
    # Install to appropriate directory (allow user override via SUIUP_INSTALL_DIR)
    install_dir="${SUIUP_INSTALL_DIR:-$(get_install_dir "$os")}"
    installed_path="$install_dir/suiup"
    if [ "$os" = "windows" ]; then
        installed_path="$install_dir/suiup.exe"
    fi
    
    printf 'Installing to %s...\n' "$installed_path"
    
    # Ensure install directory exists
    mkdir -p "$install_dir"
    
    # Move binary to install directory
    mv "$tmp_dir/suiup" "$installed_path"
    
    printf '%bSuccessfully installed suiup to %s%b\n' "${GREEN}" "$installed_path" "${NC}"
    
    # Check PATH
    check_path "$install_dir" "$os"
    
    # Check for existing binaries
    check_existing_binaries "$install_dir" "$os"
    
    printf '\n'
    printf 'You can now run %bsuiup --help%b to get started.\n' "${CYAN}" "${NC}"
    printf 'For more information, visit: https://github.com/%s\n' "$GITHUB_REPO"
}

# Run the installer
install_suiup
