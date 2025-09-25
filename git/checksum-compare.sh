#!/bin/bash
# Git Content Comparison Script - Final File Contents Only
# Compares the final working tree content of commits/branches, ignoring history
# Author: Emre Dogan
# Usage: ./git-compare-content.sh <REF_A> <REF_B> [OPTIONS]

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Options
VERBOSE=false
QUIET=false
METHOD="archive" # archive, tree, listing, diff
ALGORITHM="sha256sum"
SHOW_DIFF=false

show_help() {
  cat << EOF
Git Content Comparison - Final File Contents Only

USAGE:
    $0 <REF_A> <REF_B> [OPTIONS]

ARGUMENTS:
    REF_A       First reference (commit SHA, branch, tag, HEAD~1, etc.)
    REF_B       Second reference (commit SHA, branch, tag, HEAD, etc.)

OPTIONS:
    -m, --method        Comparison method:
                        archive  - git archive checksum (most accurate)
                        tree     - tree SHA comparison (fastest)
                        listing  - tree listing checksum (balanced)
                        diff     - git diff --quiet (standard)
                        Default: archive

    -a, --algorithm     Hash algorithm (sha256sum, sha1sum, md5sum)
                        Default: sha256sum (only for archive/listing methods)

    -v, --verbose       Show detailed output including checksums
    -q, --quiet         Suppress output, exit code only
    -d, --show-diff     Show file differences when content differs
    -h, --help          Show this help

METHODS EXPLAINED:
    archive   - Handles .gitattributes, CRLF conversion, filters (most accurate)
    tree      - Raw tree SHA comparison (fastest, ignores Git transformations)
    listing   - Tree listing checksum (fast, includes file paths)
    diff      - Standard git diff (good balance, shows differences)

EXAMPLES:
    # Compare branches (most common use case)
    $0 main develop

    # Compare commits with different histories but same content
    $0 abc1234 def5678 --method archive --verbose

    # Fast tree comparison for CI
    $0 HEAD~1 HEAD --method tree --quiet

    # Show differences when content differs
    $0 feature/branch main --show-diff

    # Compare tag with branch
    $0 v1.0.0 main --method listing

EXIT CODES:
    0    Content is identical
    1    Content differs
    2    Error (invalid refs, Git error, etc.)

NOTES:
    - Completely ignores commit history and metadata
    - Only compares final file contents at each reference
    - Two branches with different commit histories but identical
      final content will show as identical
    - Handles binary files, symlinks, and submodules
EOF
}

log() {
  local level="$1"
  shift
  local message="$*"

  [[ "$QUIET" == "true" && "$level" != "ERROR" ]] && return

  case "$level" in
    "INFO") echo -e "${BLUE}ℹ️  ${message}${NC}" >&2 ;;
    "SUCCESS") echo -e "${GREEN}✅ ${message}${NC}" >&2 ;;
    "ERROR") echo -e "${RED}❌ ${message}${NC}" >&2 ;;
    "DEBUG") [[ "$VERBOSE" == "true" ]] && echo -e "${YELLOW}🔍 ${message}${NC}" >&2 ;;
  esac
}

validate_ref() {
  local ref="$1"
  if ! git rev-parse --verify "$ref" > /dev/null 2>&1; then
    log "ERROR" "Invalid reference: '$ref'"
    return 1
  fi
  return 0
}

get_ref_info() {
  local ref="$1"
  local sha=$(git rev-parse "$ref")
  local type=$(git cat-file -t "$ref")
  local desc=""

  if [[ "$type" == "commit" ]]; then
    desc=$(git log -1 --format="%s" "$ref" 2> /dev/null || echo "No commit message")
  else
    desc="$type object"
  fi

  echo "$sha|$desc"
}

# Method 1: Archive-based comparison (most accurate)
compare_by_archive() {
  local ref_a="$1"
  local ref_b="$2"

  log "DEBUG" "Using git archive method with $ALGORITHM"

  # Create temporary files for archives
  local temp_a=$(mktemp)
  local temp_b=$(mktemp)

  # Ensure cleanup
  trap "rm -f '$temp_a' '$temp_b'" EXIT

  log "DEBUG" "Creating archive for $ref_a..."
  if ! git archive "$ref_a" > "$temp_a"; then
    log "ERROR" "Failed to create archive for $ref_a"
    rm -f "$temp_a" "$temp_b"
    return 2
  fi

  log "DEBUG" "Creating archive for $ref_b..."
  if ! git archive "$ref_b" > "$temp_b"; then
    log "ERROR" "Failed to create archive for $ref_b"
    rm -f "$temp_a" "$temp_b"
    return 2
  fi

  log "DEBUG" "Calculating checksums..."
  local checksum_a=$($ALGORITHM "$temp_a" | cut -d' ' -f1)
  local checksum_b=$($ALGORITHM "$temp_b" | cut -d' ' -f1)

  # Cleanup temp files
  rm -f "$temp_a" "$temp_b"

  if [[ "$VERBOSE" == "true" ]]; then
    echo "Archive checksums:"
    echo "  $ref_a: $checksum_a"
    echo "  $ref_b: $checksum_b"
    echo
  fi

  if [[ "$checksum_a" == "$checksum_b" ]]; then
    log "SUCCESS" "Content identical (archive checksum: ${checksum_a:0:12}...)"
    return 0
  else
    log "ERROR" "Content differs (archive checksums differ)"
    return 1
  fi
}

# Method 2: Tree SHA comparison (fastest)
compare_by_tree() {
  local ref_a="$1"
  local ref_b="$2"

  log "DEBUG" "Using tree SHA comparison method"

  local tree_a=$(git rev-parse "${ref_a}^{tree}")
  local tree_b=$(git rev-parse "${ref_b}^{tree}")

  if [[ "$VERBOSE" == "true" ]]; then
    echo "Tree SHAs:"
    echo "  $ref_a: $tree_a"
    echo "  $ref_b: $tree_b"
    echo
  fi

  if [[ "$tree_a" == "$tree_b" ]]; then
    log "SUCCESS" "Content identical (tree SHA: ${tree_a:0:12}...)"
    return 0
  else
    log "ERROR" "Content differs (tree SHAs differ)"
    return 1
  fi
}

# Method 3: Tree listing comparison (balanced)
compare_by_listing() {
  local ref_a="$1"
  local ref_b="$2"

  log "DEBUG" "Using tree listing method with $ALGORITHM"

  local listing_a=$(git ls-tree -r "$ref_a" | $ALGORITHM | cut -d' ' -f1)
  local listing_b=$(git ls-tree -r "$ref_b" | $ALGORITHM | cut -d' ' -f1)

  if [[ "$VERBOSE" == "true" ]]; then
    echo "Tree listing checksums:"
    echo "  $ref_a: $listing_a"
    echo "  $ref_b: $listing_b"
    echo
  fi

  if [[ "$listing_a" == "$listing_b" ]]; then
    log "SUCCESS" "Content identical (listing checksum: ${listing_a:0:12}...)"
    return 0
  else
    log "ERROR" "Content differs (listing checksums differ)"
    return 1
  fi
}

# Method 4: Git diff comparison (standard)
compare_by_diff() {
  local ref_a="$1"
  local ref_b="$2"

  log "DEBUG" "Using git diff method"

  if git diff --quiet "$ref_a" "$ref_b"; then
    log "SUCCESS" "Content identical (no differences in git diff)"
    return 0
  else
    log "ERROR" "Content differs (git diff found differences)"
    return 1
  fi
}

show_differences() {
  local ref_a="$1"
  local ref_b="$2"

  echo
  echo "📋 Content Differences:"
  echo "======================"

  # Show file status changes
  echo
  echo "File Status Changes:"
  git diff --name-status "$ref_a" "$ref_b" || true

  # Show summary statistics
  echo
  echo "Change Summary:"
  git diff --stat "$ref_a" "$ref_b" || true

  if [[ "$VERBOSE" == "true" ]]; then
    echo
    echo "Detailed Differences (first 50 lines):"
    echo "======================================"
    git diff "$ref_a" "$ref_b" | head -50 || true

    local total_lines=$(git diff "$ref_a" "$ref_b" | wc -l)
    if [[ $total_lines -gt 50 ]]; then
      echo "... (${total_lines} total lines of diff, showing first 50)"
    fi
  fi
}

main() {
  local ref_a=""
  local ref_b=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        show_help
        exit 0
        ;;
      -v | --verbose)
        VERBOSE=true
        shift
        ;;
      -q | --quiet)
        QUIET=true
        shift
        ;;
      -d | --show-diff)
        SHOW_DIFF=true
        shift
        ;;
      -m | --method)
        METHOD="$2"
        shift 2
        ;;
      -a | --algorithm)
        ALGORITHM="$2"
        shift 2
        ;;
      -*)
        log "ERROR" "Unknown option: $1"
        exit 2
        ;;
      *)
        if [[ -z "$ref_a" ]]; then
          ref_a="$1"
        elif [[ -z "$ref_b" ]]; then
          ref_b="$1"
        else
          log "ERROR" "Too many arguments"
          exit 2
        fi
        shift
        ;;
    esac
  done

  # Validate arguments
  if [[ -z "$ref_a" || -z "$ref_b" ]]; then
    log "ERROR" "Missing required arguments"
    echo "Usage: $0 <REF_A> <REF_B> [OPTIONS]"
    exit 2
  fi

  if [[ ! "$METHOD" =~ ^(archive|tree|listing|diff)$ ]]; then
    log "ERROR" "Invalid method: $METHOD"
    exit 2
  fi

  # Check Git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "ERROR" "Not in a Git repository"
    exit 2
  fi

  # Validate references
  validate_ref "$ref_a" || exit 2
  validate_ref "$ref_b" || exit 2

  # Get reference info
  local ref_a_info=$(get_ref_info "$ref_a")
  local ref_b_info=$(get_ref_info "$ref_b")

  log "INFO" "Comparing content: $ref_a vs $ref_b"
  log "INFO" "Method: $METHOD"

  if [[ "$VERBOSE" == "true" ]]; then
    echo
    echo "Reference A: $ref_a"
    echo "  SHA: ${ref_a_info%%|*}"
    echo "  Description: ${ref_a_info##*|}"
    echo
    echo "Reference B: $ref_b"
    echo "  SHA: ${ref_b_info%%|*}"
    echo "  Description: ${ref_b_info##*|}"
    echo
  fi

  # First, let's check if trees are identical (fastest check)
  local tree_a=$(git rev-parse "${ref_a}^{tree}")
  local tree_b=$(git rev-parse "${ref_b}^{tree}")

  if [[ "$VERBOSE" == "true" ]]; then
    echo "Tree objects:"
    echo "  $ref_a tree: $tree_a"
    echo "  $ref_b tree: $tree_b"
    echo
  fi

  # If trees are identical, content is definitely identical
  if [[ "$tree_a" == "$tree_b" ]]; then
    log "SUCCESS" "Content identical (same tree object: ${tree_a:0:12}...)"
    exit 0
  fi

  # Trees differ, so perform detailed comparison based on method
  local exit_code
  case "$METHOD" in
    "archive")
      if ! command -v "$ALGORITHM" > /dev/null 2>&1; then
        log "ERROR" "Hash algorithm not found: $ALGORITHM"
        exit 2
      fi
      # Compare tree objects directly with archive
      compare_by_archive "${tree_a}" "${tree_b}"
      exit_code=$?
      ;;
    "tree")
      # Trees already compared above
      log "ERROR" "Content differs (different tree objects)"
      exit_code=1
      ;;
    "listing")
      if ! command -v "$ALGORITHM" > /dev/null 2>&1; then
        log "ERROR" "Hash algorithm not found: $ALGORITHM"
        exit 2
      fi
      compare_by_listing "$ref_a" "$ref_b"
      exit_code=$?
      ;;
    "diff")
      compare_by_diff "$ref_a" "$ref_b"
      exit_code=$?
      ;;
  esac

  # Show differences if requested and content differs
  if [[ $exit_code -ne 0 && "$SHOW_DIFF" == "true" ]]; then
    show_differences "$ref_a" "$ref_b"
  fi

  exit $exit_code
}

main "$@"
