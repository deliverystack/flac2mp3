#!/usr/bin/bash

script_name=$(basename "$0")
source_dir="${1:-.}"
default_genre="${2:-Miscellaneous}"

shopt -s globstar

clean_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}

get_unique_genres() {
    local dir="$1"
    declare -A genres

    for file in "$dir"/*.mp3; do
        if [ -f "$file" ]; then
            genre=$(ffprobe -v error -show_entries format_tags=genre \
                -of default=noprint_wrappers=1:nokey=1 "$file" | tr -d '\r')
            if [ -n "$genre" ]; then
                genres["$genre"]=1
            fi
        fi
    done

    local genre_list=""
    local yellow=$(tput setaf 3)
    local blue=$(tput setaf 4)
    local reset=$(tput sgr0)
    for genre in "${!genres[@]}"; do
        if [ -n "$genre_list" ]; then
            genre_list+=" - "
        fi
        if [ "${#genres[@]}" -eq 1 ] && [ "$genre" == "$default_genre" ]; then
            genre_list+="${blue}$genre${reset}"
        else
            genre_list+="${yellow}$genre${reset}"
        fi
    done

    echo "$genre_list"
}

start_time=$(date +%s)

misc_dir="$source_dir/$default_genre"

if [ -d "$misc_dir" ]; then
    for artist_dir in "$misc_dir"/*; do
        if [ -d "$artist_dir" ]; then
            artist_name=$(basename "$artist_dir")

            for album_dir in "$artist_dir"/*; do
                if [ -d "$album_dir" ]; then
                    album_name=$(basename "$album_dir")
                    unique_genres=$(get_unique_genres "$album_dir")

                    current_time=$(date +%s)
                    elapsed=$((current_time - start_time))
                    printf "$(tput setaf 2)%s:$(tput sgr0) Directory $(tput setaf 2)%s/%s$(tput sgr0) has genres: %s. - Elapsed: $(tput setaf 2)%'d$(tput sgr0) seconds\n\n" \
                           "$script_name" "$artist_name" "$album_name" "$unique_genres" "$elapsed"
                fi
            done
        fi
    done
else
    printf "$(tput setaf 3)%s:$(tput sgr0) Miscellaneous directory $(tput setaf 2)%s$(tput sgr0) does not exist.\n" \
           "$script_name" "$misc_dir"
    exit 1
fi