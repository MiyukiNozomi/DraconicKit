#!/bin/sh

find "./src/template/res" -type f \( \
    -iname '*.jpg'  -o \
    -iname '*.jpeg' -o \
    -iname '*.png'  -o \
    -iname '*.gif'  -o \
    -iname '*.bmp'  -o \
    -iname '*.tiff' -o \
    -iname '*.tif'  -o \
    -iname '*.avif' -o \
    -iname '*.heic' \
\) -print | while IFS= read -r file; do
    output="${file%.*}.webp"
    if [ -e "$output" ]; then
        echo "SKIP: Destination already exists: $output"
        continue
    fi
    echo "Converting: $file"
    if convert "$file" "$output"; then
        if rm "$file"; then
            echo "OK: $file -> $output"
        else
            echo "WARNING: Converted to $output, but could not remove $file"
        fi
    else
        echo "ERROR: Failed to convert $file"
        rm -f "$output"
    fi
done
echo "Done."