#!/bin/bash

# CSV Branch Comparison Generator
# Creates aligned CSV comparing develop and main branches

OUTPUT_FILE="branch-comparison-$(date +%Y%m%d-%H%M).csv"
TEMP_DIR="temp-comparison-$$"
mkdir -p "$TEMP_DIR"

echo "Generating CSV comparison: $OUTPUT_FILE"

# Get merge base between the two branches
MERGE_BASE=$(git merge-base develop main)
echo "Using merge base: $MERGE_BASE"

# Get commits from merge base to tip for both branches
git log $MERGE_BASE..develop --pretty=format:"%h|%ad|%an|%s" --date=short > "$TEMP_DIR/develop_commits.txt"
git log $MERGE_BASE..main --pretty=format:"%h|%ad|%an|%s" --date=short > "$TEMP_DIR/main_commits.txt"

# Create CSV header
cat > "$OUTPUT_FILE" << 'EOF'
develop_hash,develop_date,develop_author,develop_message,main_hash,main_date,main_author,main_message,author_conflict
EOF

# Function to escape CSV fields
escape_csv() {
    echo "$1" | sed 's/"/""/g' | sed 's/^/"/' | sed 's/$/"/'
}

# Get unique commit messages from both branches
cat "$TEMP_DIR/develop_commits.txt" "$TEMP_DIR/main_commits.txt" | cut -d'|' -f4 | sort -u > "$TEMP_DIR/unique_messages.txt"

# Process each unique message
while IFS= read -r message; do
    # Find matching commits in develop
    develop_match=$(grep -F "$message" "$TEMP_DIR/develop_commits.txt" | head -1)
    
    # Find matching commits in main
    main_match=$(grep -F "$message" "$TEMP_DIR/main_commits.txt" | head -1)
    
    # Initialize variables
    develop_hash="" develop_date="" develop_author="" develop_message=""
    main_hash="" main_date="" main_author="" main_message=""
    author_conflict="false"
    
    # Parse develop match if exists
    if [ ! -z "$develop_match" ]; then
        IFS='|' read -r develop_hash develop_date develop_author develop_message <<< "$develop_match"
    fi
    
    # Parse main match if exists
    if [ ! -z "$main_match" ]; then
        IFS='|' read -r main_hash main_date main_author main_message <<< "$main_match"
    fi
    
    # Skip if both commits have identical hashes (same commit)
    if [ ! -z "$develop_hash" ] && [ ! -z "$main_hash" ] && [ "$develop_hash" = "$main_hash" ]; then
        continue
    fi
    
    # Check for author conflict (same message, different authors)
    if [ ! -z "$develop_match" ] && [ ! -z "$main_match" ] && [ "$develop_author" != "$main_author" ]; then
        author_conflict="true"
    fi
    
    # Escape fields for CSV
    develop_hash=$(escape_csv "$develop_hash")
    develop_date=$(escape_csv "$develop_date")
    develop_author=$(escape_csv "$develop_author")
    develop_message=$(escape_csv "$develop_message")
    main_hash=$(escape_csv "$main_hash")
    main_date=$(escape_csv "$main_date")
    main_author=$(escape_csv "$main_author")
    main_message=$(escape_csv "$main_message")
    
    # Write row to CSV
    echo "$develop_hash,$develop_date,$develop_author,$develop_message,$main_hash,$main_date,$main_author,$main_message,$author_conflict" >> "$OUTPUT_FILE"
    
done < "$TEMP_DIR/unique_messages.txt"

# Cleanup
rm -rf "$TEMP_DIR"

echo "✅ CSV generated: $OUTPUT_FILE"
echo "📊 Import into Google Sheets with File > Import > Upload"
echo ""
echo "CSV Structure:"
echo "- develop_hash, develop_date, develop_author, develop_message"
echo "- main_hash, main_date, main_author, main_message" 
echo "- author_conflict (true/false for same message, different authors)"