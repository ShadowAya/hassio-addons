#!/usr/bin/with-contenv bashio
set -euo pipefail

readonly FILEBOT_DIR="/data/filebot"
readonly FILEBOT_BIN="/data/filebot/filebot.sh"
readonly SEEN_FILE="/data/.seen_files"

WATCH_DIR=""
MOVIE_OUTPUT_TEMPLATE=""
SHOW_OUTPUT_TEMPLATE=""
MOVIE_FORMAT=""
SHOW_FORMAT=""
DATABASE=""
ACTION=""
CONFLICT=""
POLL_INTERVAL="30"
USE_INOTIFY="true"
MOVIE_PATH_VALIDATION="strict"
SHOW_PATH_VALIDATION="create_last"

MOUNTED_POINTS=()

cleanup() {
    bashio::log.info "Shutting down add-on"

    for mnt in "${MOUNTED_POINTS[@]}"; do
        if mountpoint -q "$mnt"; then
            bashio::log.info "Unmounting $mnt"
            umount "$mnt" || bashio::log.warning "Failed to unmount $mnt"
        fi
    done
}

trap cleanup SIGTERM SIGINT EXIT

normalize_null() {
    local value="$1"

    if [[ "$value" == "null" ]]; then
        printf ''
        return 0
    fi

    printf '%s' "$value"
}

sanitize_path_component() {
    local value="$1"

    value="$(echo "$value" | sed -E 's#[/\\]+#-#g; s/[._-]+/ /g; s/[[:space:]]+/ /g; s/^ +| +$//g')"
    printf '%s' "$value"
}

extract_year() {
    local name="$1"

    echo "$name" | grep -Eo '(19|20)[0-9]{2}' | head -n 1 || true
}

detect_media_type() {
    local name="$1"

    if [[ "$name" =~ [Ss][0-9]{1,2}[Ee][0-9]{1,2} ]] || [[ "$name" =~ [0-9]{1,2}[xX][0-9]{2} ]]; then
        printf 'show'
    else
        printf 'movie'
    fi
}

parse_show_name() {
    local name="$1"
    local cleaned
    local show_name

    cleaned="$(sanitize_path_component "$name")"
    show_name="$(echo "$cleaned" | sed -E 's/[[:space:]]+([Ss][0-9]{1,2}[Ee][0-9]{1,2}|[0-9]{1,2}[xX][0-9]{2}).*$//')"
    show_name="$(echo "$show_name" | sed -E 's/[[:space:]]+(19|20)[0-9]{2}$//')"
    show_name="$(sanitize_path_component "$show_name")"

    if [[ -z "$show_name" ]]; then
        show_name="Unknown Show"
    fi

    printf '%s' "$show_name"
}

parse_movie_name() {
    local name="$1"
    local cleaned
    local movie_name

    cleaned="$(sanitize_path_component "$name")"
    movie_name="$(echo "$cleaned" | sed -E 's/[[:space:]]+(19|20)[0-9]{2}.*$//')"
    movie_name="$(echo "$movie_name" | sed -E 's/[[:space:]]+(480p|720p|1080p|2160p|x264|x265|h264|h265|bluray|brrip|web[ -]?dl|webrip|dvdrip).*$//I')"
    movie_name="$(sanitize_path_component "$movie_name")"

    if [[ -z "$movie_name" ]]; then
        movie_name="Unknown Movie"
    fi

    printf '%s' "$movie_name"
}

resolve_output_template() {
    local template="$1"
    local media_type="$2"
    local show_name="$3"
    local movie_name="$4"
    local title="$5"
    local year="$6"
    local output

    output="$template"
    output="${output//<MEDIA_TYPE>/$media_type}"
    output="${output//<TYPE>/$media_type}"
    output="${output//<SHOWNAME>/$show_name}"
    output="${output//<SHOW_NAME>/$show_name}"
    output="${output//<MOVIENAME>/$movie_name}"
    output="${output//<MOVIE_NAME>/$movie_name}"
    output="${output//<TITLE>/$title}"
    output="${output//<YEAR>/$year}"
    output="$(echo "$output" | sed -E 's#//+#/#g; s#/$##')"

    printf '%s' "$output"
}

validate_output_path() {
    local path="$1"
    local mode="$2"
    local parent

    case "$mode" in
        none)
            return 0
            ;;
        strict)
            if [[ -d "$path" ]]; then
                return 0
            fi
            bashio::log.warning "Strict path validation failed: $path does not exist"
            return 1
            ;;
        create_last)
            if [[ -d "$path" ]]; then
                return 0
            fi

            parent="$(dirname "$path")"
            if [[ -d "$parent" ]]; then
                mkdir -p "$path"
                return 0
            fi

            bashio::log.warning "create_last validation failed: parent directory missing for $path"
            return 1
            ;;
        *)
            bashio::log.warning "Unknown path validation mode '$mode', using strict"
            if [[ -d "$path" ]]; then
                return 0
            fi
            return 1
            ;;
    esac
}

log_mount_listing() {
    local mnt="$1"
    local max_lines="25"

    bashio::log.info "Mount listing for $mnt (first $max_lines lines)"
    ls -la "$mnt" 2>&1 | head -n "$max_lines" |
    while IFS= read -r line; do
        bashio::log.info "[ls $mnt] $line"
    done
}

download_filebot() {
    if [[ -x "$FILEBOT_BIN" ]]; then
        bashio::log.info "Using existing FileBot CLI at $FILEBOT_BIN"
        return 0
    fi

    local download_page
    local portable_url
    local archive_file

    download_page="$(mktemp)"
    archive_file="$(mktemp)"

    if ! curl -fsSL "https://www.filebot.net/download.html" -o "$download_page"; then
        rm -f "$download_page" "$archive_file"
        bashio::log.fatal "Could not fetch FileBot download page"
        exit 1
    fi

    portable_url="$(grep -Eo 'https://get\.filebot\.net/filebot/FileBot_[^" )]+-portable\.tar\.xz' "$download_page" | head -n 1 || true)"
    rm -f "$download_page"

    if [[ -z "$portable_url" ]]; then
        rm -f "$archive_file"
        bashio::log.fatal "Could not determine FileBot portable download URL"
        exit 1
    fi

    bashio::log.info "Downloading FileBot CLI bundle from $portable_url"

    if ! curl -fsSL "$portable_url" -o "$archive_file"; then
        rm -f "$archive_file"
        bashio::log.fatal "Failed to download FileBot portable archive"
        exit 1
    fi

    rm -rf "$FILEBOT_DIR"
    mkdir -p "$FILEBOT_DIR"

    if ! xz -dc "$archive_file" | tar -xf - -C "$FILEBOT_DIR"; then
        rm -f "$archive_file"
        bashio::log.fatal "Failed to extract FileBot portable archive"
        exit 1
    fi

    rm -f "$archive_file"
    chmod +x "$FILEBOT_BIN"

    if [[ ! -x "$FILEBOT_BIN" ]]; then
        bashio::log.fatal "FileBot CLI executable not found after extraction"
        exit 1
    fi

    bashio::log.info "FileBot CLI installed at $FILEBOT_BIN"
}

read_config() {
    WATCH_DIR="$(normalize_null "$(bashio::config 'watch_folder')")"
    MOVIE_OUTPUT_TEMPLATE="$(normalize_null "$(bashio::config 'movie_output_folder')")"
    SHOW_OUTPUT_TEMPLATE="$(normalize_null "$(bashio::config 'show_output_folder')")"
    MOVIE_FORMAT="$(normalize_null "$(bashio::config 'movie_format')")"
    SHOW_FORMAT="$(normalize_null "$(bashio::config 'show_format')")"
    DATABASE="$(normalize_null "$(bashio::config 'database')")"
    ACTION="$(normalize_null "$(bashio::config 'action')")"
    CONFLICT="$(normalize_null "$(bashio::config 'conflict')")"
    POLL_INTERVAL="$(normalize_null "$(bashio::config 'poll_interval')")"
    USE_INOTIFY="$(normalize_null "$(bashio::config 'use_inotify')")"
    MOVIE_PATH_VALIDATION="$(normalize_null "$(bashio::config 'movie_path_validation')")"
    SHOW_PATH_VALIDATION="$(normalize_null "$(bashio::config 'show_path_validation')")"

    if [[ -z "$WATCH_DIR" ]]; then
        bashio::log.fatal "watch_folder must be set"
        exit 1
    fi

    if [[ -z "$MOVIE_OUTPUT_TEMPLATE" || -z "$SHOW_OUTPUT_TEMPLATE" ]]; then
        bashio::log.fatal "movie_output_folder and show_output_folder must both be set"
        exit 1
    fi

    if [[ -z "$MOVIE_FORMAT" || -z "$SHOW_FORMAT" ]]; then
        bashio::log.fatal "movie_format and show_format must both be set"
        exit 1
    fi

    if [[ -z "$MOVIE_PATH_VALIDATION" ]]; then
        MOVIE_PATH_VALIDATION="strict"
    fi

    if [[ -z "$SHOW_PATH_VALIDATION" ]]; then
        SHOW_PATH_VALIDATION="create_last"
    fi

    if [[ -z "$POLL_INTERVAL" ]]; then
        POLL_INTERVAL="30"
    fi

    if [[ -z "$USE_INOTIFY" ]]; then
        USE_INOTIFY="true"
    fi

    touch "$SEEN_FILE"
}

mount_local_partitions() {
    local options_path
    local mount_failures
    local -a mount_items
    options_path="/data/options.json"
    mount_failures="0"

    if [[ ! -f "$options_path" ]]; then
        bashio::log.warning "Options file not found at $options_path, skipping mount processing"
        return 0
    fi

    mapfile -t mount_items < <(
        jq -r '.mounts // [] | if type == "array" then .[] elif type == "string" then . else empty end' "$options_path" 2>/dev/null || true
    )

    if (( ${#mount_items[@]} == 0 )); then
        bashio::log.info "No mounts configured"
        return 0
    fi

    for mount_item in "${mount_items[@]}"; do
        mount_item="$(normalize_null "$mount_item")"
        [[ -z "$mount_item" ]] && continue

        local dev
        local partition
        local mnt

        if [[ "$mount_item" == /dev/* ]]; then
            dev="$mount_item"
            partition="${mount_item##*/}"
        else
            partition="$mount_item"
            dev="/dev/$mount_item"
        fi

        mnt="/mnt/$partition"

        if [[ ! -b "$dev" ]]; then
            bashio::log.warning "Device not found: $dev"
            mount_failures=$((mount_failures + 1))
            continue
        fi

        mkdir -p "$mnt"

        if mountpoint -q "$mnt"; then
            bashio::log.info "$mnt already mounted"
            log_mount_listing "$mnt"
            continue
        fi

        bashio::log.info "Mounting $dev at $mnt"
        if mount -t auto "$dev" "$mnt"; then
            MOUNTED_POINTS+=("$mnt")
        else
            bashio::log.warning "Mount command failed for $dev"
        fi

        if mountpoint -q "$mnt"; then
            bashio::log.info "Mounted $dev successfully at $mnt"
            log_mount_listing "$mnt"
        else
            bashio::log.warning "Failed to mount $dev"
            mount_failures=$((mount_failures + 1))
        fi
    done

    if (( mount_failures > 0 )); then
        bashio::log.fatal "$mount_failures configured mount(s) failed; stopping startup"
        return 1
    fi
}

ensure_watch_folder_exists() {
    if [[ ! -d "$WATCH_DIR" ]]; then
        bashio::log.fatal "watch_folder does not exist after mount checks: $WATCH_DIR"
        return 1
    fi

    bashio::log.info "watch_folder is available: $WATCH_DIR"
}

run_filebot() {
    local file="$1"
    local filename
    local name_no_ext
    local media_type
    local year
    local show_name
    local movie_name
    local title
    local output_template
    local output_dir
    local format
    local validation_mode

    if [[ ! -f "$file" ]]; then
        bashio::log.warning "Skipping non-file path: $file"
        return 0
    fi

    filename="${file##*/}"
    name_no_ext="${filename%.*}"
    media_type="$(detect_media_type "$name_no_ext")"
    year="$(extract_year "$name_no_ext")"
    show_name="$(parse_show_name "$name_no_ext")"
    movie_name="$(parse_movie_name "$name_no_ext")"

    if [[ "$media_type" == "show" ]]; then
        title="$show_name"
        output_template="$SHOW_OUTPUT_TEMPLATE"
        format="$SHOW_FORMAT"
        validation_mode="$SHOW_PATH_VALIDATION"
    else
        title="$movie_name"
        output_template="$MOVIE_OUTPUT_TEMPLATE"
        format="$MOVIE_FORMAT"
        validation_mode="$MOVIE_PATH_VALIDATION"
    fi

    output_dir="$(resolve_output_template "$output_template" "$media_type" "$show_name" "$movie_name" "$title" "$year")"

    if ! validate_output_path "$output_dir" "$validation_mode"; then
        bashio::log.warning "Skipping file due to output path validation failure: $file"
        return 0
    fi

    bashio::log.info "Processing file: $file (type=$media_type, output=$output_dir)"

    if ! "$FILEBOT_BIN" -rename "$file" \
        --output "$output_dir" \
        --format "$format" \
        --db "$DATABASE" \
        --action "$ACTION" \
        --conflict "$CONFLICT" \
        -non-strict; then
        bashio::log.warning "FileBot failed for $file"
    fi
}

poll_loop() {
    bashio::log.info "Using polling mode every $POLL_INTERVAL seconds"

    while true; do
        while IFS= read -r -d '' filepath; do
            if ! grep -Fxq "$filepath" "$SEEN_FILE"; then
                echo "$filepath" >> "$SEEN_FILE"
                run_filebot "$filepath"
            fi
        done < <(find "$WATCH_DIR" -type f -print0)

        sleep "$POLL_INTERVAL"
    done
}

inotify_loop() {
    bashio::log.info "Using inotify mode"

    inotifywait -m -e close_write,moved_to --format '%w%f' "$WATCH_DIR" |
    while IFS= read -r filepath; do
        run_filebot "$filepath"
    done
}

main() {
    read_config
    mount_local_partitions
    ensure_watch_folder_exists
    download_filebot

    if [[ "$USE_INOTIFY" == "true" ]] && command -v inotifywait >/dev/null 2>&1; then
        if ! inotify_loop; then
            bashio::log.warning "inotify loop exited, falling back to polling"
            poll_loop
        fi
    else
        poll_loop
    fi
}

main
