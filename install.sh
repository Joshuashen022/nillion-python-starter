#!/usr/bin/env bash

set -o errexit

BASE_DOWNLOAD_URL="https://releases.nilogy.xyz/sdk/latest"
MACOS_VOLUME_NAME="nillion-sdk"
MACOS_VOLUME_PATH="/Volumes/${MACOS_VOLUME_NAME}"

check_download() {
    local url="${1:?url is required by check_download}"

    local status_code

    if ! status_code=$(curl -I -L -o /dev/null -s -w "%{http_code}" "$url"); then
        print_unexpected_error "Fetching headers for '$url' failed."
        exit 1
    fi

    if [[ "$status_code" != "200" ]]; then
        print_unexpected_error "Fetching headers for '$url' failed: $status_code."
        exit 1
    fi
}

check_program() {
    local program="${1:?program is required by check_program}"

    if ! command -v "$program" >/dev/null; then
        print_error "$program not found. Install it and place it in your \$PATH."
        exit 1
    fi
}

create_install_dir() {
    local nillion_bin="$HOME/.nilup/bin"

    mkdir -p "$nillion_bin"

    echo "$nillion_bin"
}

detect_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        aarch64|arm64)
            echo "aarch64"
            ;;
        x86_64)
            echo "x86_64"
            ;;
        *)
            print_platform_not_supported "$arch"
            exit 1
            ;;
    esac
}

detect_platform() {
    local kernel
    kernel=$(uname -s)

    case "$kernel" in
        Darwin|Linux)
            true
            ;;
        *)
            print_platform_not_supported "$kernel"
            exit 1
            ;;
    esac

    echo "$kernel" | tr '[:upper:]' '[:lower:]'
}

detect_profile() {
    case "$SHELL" in
        */ash)
            echo "$HOME/.profile"
            ;;
        */bash)
            echo "$HOME/.bashrc"
            ;;
        */fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        */zsh)
            echo "$HOME/.zshenv"
            ;;
        *)
            return 1
            ;;
    esac
}

detect_target() {
    local platform
    platform=$(detect_platform)

    local arch
    arch=$(detect_arch)

    case "$platform" in
        darwin)
            echo "$arch-apple-darwin"
            ;;
        linux)
            echo "$arch-unknown-linux-musl"
            ;;
        *)
            print_platform_not_supported "$kernel"
            exit 1
            ;;
    esac
}

download() {
    local download_dir="${1:?download_dir is required by download}"
    local download_url="${2:?download_url is required by download}"

    (
        cd "$download_dir"

        if ! curl -L -O -s "$download_url"; then
            print_unexpected_error "Download of '$download_url' into '$download_dir' failed."
            return 1
        fi
    )
}

get_download_url() {
    local platform
    platform=$(detect_platform)

    local target
    target=$(detect_target)

    case "$platform" in
        darwin)
            echo "$BASE_DOWNLOAD_URL/nillion-sdk-bins-$target.dmg"
            ;;
        linux)
            echo "$BASE_DOWNLOAD_URL/nillion-sdk-bins-$target.tar.gz"
            ;;
        *)
            print_platform_not_supported "$platform"
            exit 1
            ;;
    esac
}

install() {
    local download_dir="${1:?download_dir is required by install}"
    local install_dir="${2:?install_dir is required by install}"
    local archive_file="${3:?archive_file is required by install}"

    local platform
    platform=$(detect_platform)

    case "$platform" in
        darwin)
            install_macos "$download_dir" "$install_dir" "$archive_file"
            ;;
        linux)
            install_linux "$download_dir" "$install_dir" "$archive_file"
            ;;
        *)
            print_platform_not_supported "$platform"
            return 1
            ;;
    esac
}

install_linux() {
    local download_dir="${1:?download_dir is required by install_linux}"
    local install_dir="${2:?install_dir is required by install_linux}"
    local archive_file="${3:?archive_file is required by install_linux}"

    # Extract the nilup archive.
    check_program "tar"

    if ! tar xfz "$download_dir/$archive_file" -C "$download_dir"; then
        print_unexpected_error "Could not extract nilup archive '$download_dir/$archive_file'."
        return 1
    fi

    # Install nilup.
    local nilup_bin
    nilup_bin="$download_dir/nilup"

    if [[ ! -e "$nilup_bin" ]]; then
        print_unexpected_error "nilup is not present in archive."
        return 1
    fi

    cp "$nilup_bin" "$install_dir"
    chmod +x "$install_dir/nilup"
}

unmount_macos() {
    diskutil unmountDisk "$MACOS_VOLUME_PATH" &> /dev/null
    diskutil eject "$MACOS_VOLUME_NAME"  &> /dev/null
}

install_macos() {
    local download_dir="${1:?download_dir is required by install_macos}"
    local install_dir="${2:?install_dir is required by install_macos}"
    local archive_file="${3:?archive_file is required by install_macos}"

    check_program "diskutil"
    check_program "hdiutil"

    # unmount the disk image if previous failures have caused
    # the script to exit prematurely
    if test -d $MACOS_VOLUME_PATH; then
	unmount_macos
    fi

    if ! hdiutil attach "$download_dir/$archive_file" &> /dev/null; then
        print_unexpected_error "Mounting archive '$download_dir/$archive_file' failed."
        return 1
    fi

    # make sure we unmount upon exit
    trap unmount_macos EXIT

    # Install nilup.
    local nilup_bin
    nilup_bin="${MACOS_VOLUME_PATH}/nilup"

    if [[ ! -e "$nilup_bin" ]]; then
        print_unexpected_error "nilup is not present in archive."
        return 1
    fi

    cp "$nilup_bin" "$install_dir"
    chmod +x "$install_dir/nilup"
}

print_unexpected_error() {
    local message="${1:?message is required by print_unexpected_error}"

    cat <<EOF >&2
Install failed with an unexpected error:

$message

Go to Nillion's Community and Support page and report this as a support issue:
https://docs.nillion.com/community-and-support.
EOF
}

nilup_init() {
    local install_dir="${1:?install_dir is required by nilup_init}"

    echo -e "Running 'nilup init' to install the latest version of the SDK:\n"

    if ! "$install_dir"/nilup init; then
        print_unexpected_error "nilup init command failed."
        exit 1
    fi
}

print_platform_not_supported() {
    local platform="${1:?platform is required by print_platform_not_supported}"

    cat <<EOF >&2
The Nillion SDK does not support the '$platform' platform.

Please see the Developer Quickstart for more on supported platforms:
https://docs.nillion.com/quickstart.
EOF
}

check_program "curl"

# Check download exists.
DOWNLOAD_URL=$(get_download_url)
check_download "$DOWNLOAD_URL"

# Download nilup.
DOWNLOAD_DIR=$(mktemp -d)
if ! download "$DOWNLOAD_DIR" "$DOWNLOAD_URL"; then
    rm -rf "$DOWNLOAD_DIR"
    exit 1
fi

# Install nilup.
ARCHIVE_FILE=$(basename "$DOWNLOAD_URL")

if [ ! -e "$DOWNLOAD_DIR/$ARCHIVE_FILE" ]; then
    print_unexpected_error "Archive file '$ARCHIVE_FILE' is not present in download dir '$DOWNLOAD_DIR'."
    exit 1
fi

INSTALL_DIR=$(create_install_dir)
if ! install "$DOWNLOAD_DIR" "$INSTALL_DIR" "$ARCHIVE_FILE"; then
    rm -rf "$DOWNLOAD_DIR"
    exit 1
fi

# Announce that nilup has been installed and provide a convenience for users by
# adding the install dir to one's $PATH, when possible.
if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
    cat <<EOF >&2

nilup has been installed into $INSTALL_DIR.

\$PATH is already up-to-date. You may begin using nilup now!

EOF
elif PROFILE=$(detect_profile) && test -w "$PROFILE"; then
    # Add to $PATH.
    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$PROFILE"

    cat <<EOF >&2

nilup has been installed into $INSTALL_DIR and added to your \$PATH in $PROFILE.

Run 'source $PROFILE' or start a new terminal session to use nilup.

EOF
else
    cat <<EOF >&2

nilup has been installed into $INSTALL_DIR.

Redirect the output of the following command to your shell's startup file and
then run 'source $PROFILE' or start a new terminal session to use nilup:

echo 'export PATH="\$PATH:$INSTALL_DIR"' >> REPLACE_WITH_STARTUP_FILE

EOF
fi

rm -rf "$DOWNLOAD_DIR"

nilup_init "$INSTALL_DIR"
