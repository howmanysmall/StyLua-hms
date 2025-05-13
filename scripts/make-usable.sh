#!/usr/bin/env bash

# Usage: ./make_executable.sh [directory]
# If no directory is given, defaults to the current directory.

DIR="${1:-.}"

# Loop over each item in the directory
for FILE in "$DIR"/*; do
	# Only apply to regular files
	if [ -f "$FILE" ]; then
		chmod +x "$FILE"
		echo "Made executable: $FILE"
	fi
done
