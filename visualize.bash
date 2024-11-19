#!/bin/bash

# Enable globstar for recursive globbing
shopt -s globstar

# Variables
script_name=$(basename "$0")
output_file="./music_metadata.csv"
album_counts_file="./album_counts.csv"
track_counts_by_genre_file="./track_counts_by_genre.csv"
artist_track_counts_file="./artist_track_counts.csv"
invalid_years_file="./invalid_years.csv"
temp_python_script=$(mktemp /tmp/timeline_script.XXXXXX.py)
python_venv="${HOME}/python-venv"

# Define colors for echoing messages
info() { printf "\033[0;32m%s\033[0m: %s\n" "$script_name" "$1"; }
warn() { printf "\033[0;33m%s\033[0m: %s\n" "$script_name" "$1"; }
error() { printf "\033[0;31m%s\033[0m: %s\n" "$script_name" "$1"; }

# Create and activate Python virtual environment
if [[ ! -d "$python_venv" ]]; then
    info "Creating Python virtual environment at $python_venv..."
    python3 -m venv "$python_venv" || { error "Failed to create virtual environment."; exit 1; }
fi

source "$python_venv/bin/activate" || { error "Failed to activate virtual environment."; exit 1; }

# Install required Python packages if not already installed
pip install --quiet pandas plotly || { error "Failed to install required Python packages."; exit 1; }

# Function to sanitize artist names
sanitize_artist() {
    local raw_artist="$1"

    # Replace non-alphanumeric characters (excluding spaces, dashes, and letters) with dashes
    local sanitized=$(echo "$raw_artist" | sed 's/[^a-zA-Z0-9 -]/-/g')
    
    # Replace multiple dashes with a single dash
    sanitized=$(echo "$sanitized" | sed 's/-\{2,\}/-/g')
    
    # Remove leading and trailing dashes
    sanitized=$(echo "$sanitized" | sed 's/^-//;s/-$//')

    # Ensure sanitized artist name is non-empty
    [[ -z "$sanitized" ]] && sanitized="Unknown-Artist"

    echo "$sanitized"
}

# Function to extract metadata efficiently
extract_metadata() {
    local flac_file="$1"
    local dir="$2"

    # Extract all metadata
    local metadata=$(metaflac --export-tags-to=- "$flac_file")

    # Parse required fields
    local album=$(echo "$metadata" | grep -m1 '^ALBUM=' | sed 's/^ALBUM=//')
    local year=$(echo "$metadata" | grep -m1 '^YEAR=' | sed 's/^YEAR=//')
    local genre=$(echo "$metadata" | grep -m1 '^GENRE=' | sed 's/^GENRE=//')
    local artist=$(echo "$metadata" | grep -m1 '^ARTIST=' | sed 's/^ARTIST=//')

    # Fallbacks for missing or invalid values
    [[ -z "$album" ]] && album="Unknown Album"
    [[ -z "$genre" ]] && genre="Unknown Genre"
    [[ -z "$artist" ]] && artist="Unknown Artist"
    if [[ -z "$year" || ! "$year" =~ ^[0-9]{4}$ ]]; then
        # Write invalid entries to a separate file
        printf '"%s","%s","%s","%s","%s","%s"\n' "$flac_file" "$album" "$year" "$genre" "$artist" "$dir" >> "$invalid_years_file"
        return 1  # Indicate invalid year
    fi

    # Escape any internal quotes or commas in fields
    album=$(echo "$album" | sed 's/"/""/g')
    genre=$(echo "$genre" | sed 's/"/""/g')
    artist=$(echo "$artist" | sed 's/"/""/g')
    dir=$(echo "$dir" | sed 's/"/""/g')

    # Output as CSV row with proper quoting
    printf '"%s","%s","%s","%s","%s"\n' "$album" "$year" "$genre" "$artist" "$dir"
    return 0
}

# Declare associative arrays for counts
declare -A genre_counts
declare -A artist_track_counts

# Initialize output files with headers
echo "album,year,genre,artist,dir" > "$output_file"
echo "album,track_count" > "$album_counts_file"
echo "genre,track_count" > "$track_counts_by_genre_file"
echo "artist,track_count" > "$artist_track_counts_file"
echo "file_path,album,year,genre,artist,dir" > "$invalid_years_file"

# Iterate through directories and handle files
info "Scanning directory hierarchy for .flac files..."
for dir in "$1"/**/; do
    flac_files=("$dir"/*.flac)
    track_count=${#flac_files[@]}

    # Skip directories without .flac files
    if [[ "$track_count" -eq 0 || ! -f "${flac_files[0]}" ]]; then
        warn "No .flac files found in $dir. Skipping."
        continue
    fi

    # Track the number of tracks in each directory
    album_name=$(basename "$dir")
    printf '"%s","%d"\n' "$album_name" "$track_count" >> "$album_counts_file"

    # Process each track for genre extraction
    for flac_file in "${flac_files[@]}"; do
        # Extract genre and increment its count
        genre=$(metaflac --export-tags-to=- "$flac_file" | grep -m1 '^GENRE=' | sed 's/^GENRE=//')
        [[ -z "$genre" ]] && genre="Unknown Genre"
        genre_counts["$genre"]=$((genre_counts["$genre"] + 1))

        # Extract metadata and add to artist counts
        metadata=$(extract_metadata "$flac_file" "$dir")
        if [[ $? -eq 0 ]]; then
            echo "$metadata" >> "$output_file"
            artist=$(echo "$metadata" | cut -d',' -f4 | tr -d '"')
            artist=$(sanitize_artist "$artist")

            # Log for debugging
            echo "Processing sanitized artist: [$artist]" >> debug_artist_names.log

            # Increment track count for the artist
            artist_track_counts["$artist"]=$((artist_track_counts["$artist"] + 1))
        fi
    done
done

# Write genre counts to CSV
for genre in "${!genre_counts[@]}"; do
    printf '"%s","%d"\n' "$genre" "${genre_counts["$genre"]}" >> "$track_counts_by_genre_file"
done

# Write artist track counts to CSV
for artist in "${!artist_track_counts[@]}"; do
    printf '"%s","%d"\n' "$artist" "${artist_track_counts["$artist"]}" >> "$artist_track_counts_file"
done

info "Metadata extraction complete. Saved to $output_file, $album_counts_file, $track_counts_by_genre_file, and $artist_track_counts_file."

# Generate Python script for visualizations
cat <<EOF > "$temp_python_script"
import pandas as pd
import plotly.express as px

# Visualization 1: Timeline by Album Year
metadata_file = "$output_file"
df = pd.read_csv(metadata_file)
if 'year' in df.columns:
    df['year'] = pd.to_numeric(df['year'], errors='coerce')
    df = df.dropna(subset=['year'])
    timeline = df.groupby('year').size().reset_index(name='release_count')
    fig1 = px.line(timeline, x="year", y="release_count", title="Music Release Timeline")
    fig1.write_html("timeline.html")
    print("Timeline visualization saved as timeline.html")
else:
    print("The 'year' column is missing from the dataset. Skipping timeline visualization.")

# Visualization 2: Track Count by Artist
artist_track_counts_file = "$artist_track_counts_file"
df_artist = pd.read_csv(artist_track_counts_file, names=["artist", "track_count"], skiprows=1)
fig2 = px.bar(df_artist, x="artist", y="track_count", title="Track Count by Artist")
fig2.write_html("artist_track_count.html")
print("Track count visualization saved as artist_track_count.html")

# Visualization 3: Track Count by Genre
track_counts_by_genre_file = "$track_counts_by_genre_file"
df_genre = pd.read_csv(track_counts_by_genre_file, names=["genre", "track_count"], skiprows=1)
df_genre["track_count"] = pd.to_numeric(df_genre["track_count"], errors="coerce")
fig3 = px.treemap(df_genre, path=["genre"], values="track_count", title="Track Count by Genre")
fig3.write_html("track_count_by_genre_treemap.html")
print("Track count visualization saved as track_count_by_genre_treemap.html")

# Visualization 4: Album Count by Artist
df_album_artist = df.groupby('artist')['album'].nunique().reset_index(name='album_count')
fig4 = px.bar(df_album_artist, x="artist", y="album_count", title="Album Count by Artist")
fig4.write_html("album_count_by_artist.html")
print("Album count visualization saved as album_count_by_artist.html")

# Visualization 5: Album Count by Genre
df_album_genre = df.groupby('genre')['album'].nunique().reset_index(name='album_count')
fig5 = px.bar(df_album_genre, x="genre", y="album_count", title="Album Count by Genre")
fig5.write_html("album_count_by_genre.html")
print("Album count visualization saved as album_count_by_genre.html")
EOF

info "Python script generated at $temp_python_script."

# Execute the Python script using the virtual environment
"$python_venv/bin/python" "$temp_python_script" || { error "Python script execution failed."; exit 1; }

# Clean
rm -f "$temp_python_script"
info "Temporary Python script cleaned up."