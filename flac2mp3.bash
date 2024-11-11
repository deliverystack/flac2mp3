#!/usr/bin/bash

script_name=$(basename "$0")

clean_name() {
    local name="$1"
    echo "$name" | sed "s/^ *//; s/ *$//; s/'//g"
}

if [ -z "$1" ] || [ -z "$2" ]; then
    printf "\033[0;31m%s:\033[0m Usage: \033[0;32m%s\033[0m <source_dir> <target_dir>\n" \
        "$script_name" "$script_name"
    exit 1
fi

source_dir="$1"
target_dir="$2"

if ! mkdir -p "$source_dir"; then
    printf "\033[0;31m%s:\033[0m Error: Cannot create directory \033[0;32m%s\033[0m\n" \
        "$script_name" "$source_dir"
    exit 1
fi

if ! mkdir -p "$target_dir"; then
    printf "\033[0;31m%s:\033[0m Error: Cannot create directory \033[0;32m%s\033[0m\n" \
        "$script_name" "$target_dir"
    exit 1
fi

start_time=$(date +%s)
printf "\033[0;32m%s:\033[0m Finding .flac files.\n" "$script_name"
files=$(find "$source_dir" -name "*.flac")

if [[ -z "$files" ]]; then
    printf "\033[0;32m%s:\033[0m No .flac files found.\n" "$script_name"
    exit 0
fi

total=0
while IFS= read -r file; do
    ((total=total+1))
done <<< "$files"

total_formatted=$(printf "%'d" $total)
count=0
files_with_errors=()

while IFS= read -r file; do
    artist=$(metaflac "$file" --show-tag=artist | sed 's/.*=//g')
    title=$(metaflac "$file" --show-tag=title | sed 's/.*=//g')
    album=$(metaflac "$file" --show-tag=album | sed 's/.*=//g')
    genre=$(metaflac "$file" --show-tag=genre | sed 's/.*=//g')
    tracknumber=$(metaflac "$file" --show-tag=tracknumber | sed 's/.*=//g')
    date=$(metaflac "$file" --show-tag=date | sed 's/.*=//g')
    relative_path=$(clean_name "${file#$source_dir/}")
    mp3_path="$target_dir/${relative_path%.flac}.mp3"
    mkdir -p "$(dirname "$mp3_path")"
    ((count=count+1))

    flac --stdout --silent --decode "$file" | lame --silent -m j -q 0 --vbr-new -V 0 -s 44.1 \
        --tt "$title" --tn "${tracknumber:-0}" --ta "$artist" --tl "$album" \
        --ty "$date" --tg "${genre:-12}" - "$mp3_path" > /dev/null 2>&1
                
    if [[ ${PIPESTATUS[0]} -ne 0 || ${PIPESTATUS[1]} -ne 0 ]]; then
        files_with_errors+=("$file")
    fi

    error_count=${#files_with_errors[@]}
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    printf "\033[0;32m%s:\033[0m File \033[0;32m%s\033[0m of \033[0;32m%s\033[0m : \033[0;35m%s\033[0m (Errors: \033[0;31m%'d\033[0m) - Elapsed: \033[0;32m%'d\033[0m seconds\n" \
        "$script_name" "$(printf "%'d" $count)" "$total_formatted" "$file" "$error_count" "$elapsed"
done <<< "$files"

if [[ ${#files_with_errors[@]} -ne 0 ]]; then
    printf "\033[0;31m%s:\033[0m Files with errors:\n" "$script_name"
    for error_file in "${files_with_errors[@]}"; do
        printf "\033[0;31m%s:\033[0m %s\n" "$script_name" "$error_file"
    done
fi
