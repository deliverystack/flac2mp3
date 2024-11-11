#!/usr/bin/bash

script_name=$(basename "$0")
source_dir="$1"
target_dir="$2"
default_genre="${3:-Miscellaneous}"

if [ -z "$source_dir" ] || [ -z "$target_dir" ]; then
    printf "\033[0;33m%s:\033[0m Usage: \033[0;32m%s\033[0m <source_dir> <target_dir> [default_genre]\033[0m\n" \
           "$script_name" "$script_name"
    exit 1
fi

get_genre() {
    local album_dir="$1"
    local genre=""

    for file in "$album_dir"/*.mp3; do
        if [ -f "$file" ]; then
            current_genre=$(ffprobe -v error -show_entries format_tags=genre \
                -of default=noprint_wrappers=1:nokey=1 "$file")

            if [ -z "$genre" ]; then
                genre="$current_genre"
            elif [ "$genre" != "$current_genre" ]; then
                echo "$default_genre"
                return 1
            fi
        fi
    done

    echo "$genre"
    return 0
}

for artist_dir in "$source_dir"/*; do
    if [ -d "$artist_dir" ]; then
        artist_name=$(basename "$artist_dir")

        for album_dir in "$artist_dir"/*; do
            if [ -d "$album_dir" ]; then
                album_name=$(basename "$album_dir")
                genre=$(get_genre "$album_dir")

                if [ -z "$genre" ]; then
                    genre="$default_genre"
                fi

                target_genre_dir="$target_dir/$genre"
                target_artist_dir="$target_genre_dir/$artist_name"
                target_album_dir="$target_artist_dir/$album_name"
                mkdir -p "$target_album_dir"

                for track in "$album_dir"/*.mp3; do
                    if [ -f "$track" ]; then
                        track_name=$(basename "$track")
                        cp "$track" "$target_album_dir/$track_name"
                    fi
                done

                printf "\033[0;32m%s: " \
                       "Copied \033[0;32m%s\033[0m by \033[0;32m%s\033[0m to \033[0;32m%s\033[0m.\033[0m\n" \
                       "$script_name" "$album_name" "$artist_name" "$target_album_dir"
            fi
        done
    fi
done
