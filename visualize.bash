#!/bin/bash

# Enable globstar for recursive globbing
shopt -s globstar

# Variables
script_name=$(basename "$0")
output_file="./music_metadata.csv"
album_counts_file="./album_counts.csv"
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
    if [[ -z "$year" || ! "$year" =~ ^[0-9]{4}$ ]]; then
#        warn "Invalid YEAR for album '$album' in directory: $dir. Storing in invalid_years.csv"
        printf '"%s","%s","%s","%s","%s"\n' "$album" "$year" "$genre" "$artist" "$dir" >> "$invalid_years_file"
        return 1
    fi
    [[ -z "$genre" ]] && genre="Unknown Genre"
    [[ -z "$artist" ]] && artist="Unknown Artist"

    # Escape any internal quotes or commas in fields
    album=$(echo "$album" | sed 's/"/""/g')
    genre=$(echo "$genre" | sed 's/"/""/g')
    artist=$(echo "$artist" | sed 's/"/""/g')
    dir=$(echo "$dir" | sed 's/"/""/g')

    # Output as CSV row with proper quoting
    printf '"%s","%s","%s","%s","%s"\n' "$album" "$year" "$genre" "$artist" "$dir"
    return 0
}

# Initialize output files with headers
echo "album,year,genre,artist,dir" > "$output_file"
echo "album,track_count" > "$album_counts_file"
echo "album,year,genre,artist,dir" > "$invalid_years_file"

# Iterate through directories and handle files
info "Scanning directory hierarchy for .flac files..."
for dir in "$1"/**/; do
    # Get all .flac files in the current directory
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

    # Try the first file, then the third if necessary
    if ! metadata=$(extract_metadata "${flac_files[0]}" "$dir"); then
        warn "First file in $dir is invalid. Trying the third file."
        if [[ "$track_count" -ge 3 ]]; then
            metadata=$(extract_metadata "${flac_files[2]}" "$dir") || {
                error "Third file in $dir is also invalid. Skipping directory."
                continue
            }
        else
            error "Not enough files in $dir to recover metadata. Skipping directory."
            continue
        fi
    fi

    echo "$metadata" >> "$output_file"
done

info "Metadata extraction complete. Saved to $output_file, $album_counts_file, and $invalid_years_file."

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

# Visualization 2: Album Track Count Distribution
album_counts_file = "$album_counts_file"
df_counts = pd.read_csv(album_counts_file)
track_distribution = df_counts.groupby('track_count').size().reset_index(name='album_count')
fig2 = px.bar(track_distribution, x="track_count", y="album_count", title="Album Track Count Distribution")
fig2.write_html("track_distribution.html")
print("Track distribution visualization saved as track_distribution.html")

# Visualization 3: Album Count by Artist
artist_album_count = df.groupby('artist')['album'].nunique().reset_index(name='album_count')
fig3 = px.bar(artist_album_count, x="artist", y="album_count", title="Album Count by Artist")
fig3.write_html("artist_album_count.html")
print("Album count visualization saved as artist_album_count.html")

# Visualization 4: Track Count by Artist
artist_track_count = df.groupby('artist').size().reset_index(name='track_count')
fig4 = px.bar(artist_track_count, x="artist", y="track_count", title="Track Count by Artist")
fig4.write_html("artist_track_count.html")
print("Track count visualization saved as artist_track_count.html")
EOF

info "Python script generated at $temp_python_script."

# Execute the Python script using the virtual environment
"$python_venv/bin/python" "$temp_python_script" || { error "Python script execution failed."; exit 1; }

# Clean up temporary Python script
rm -f "$temp_python_script"
info "Temporary Python script cleaned up."
