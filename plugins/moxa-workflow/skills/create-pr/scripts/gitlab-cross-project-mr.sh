#!/bin/bash
#
# GitLab Cross-Project Merge Request Creator
# Creates MR from fork to upstream project
#
# Usage: gitlab-cross-project-mr.sh <source_branch> <target_branch> <title> [description]
#
# Environment:
#   GITLAB_PERSONAL_ACCESS_TOKEN - GitLab API token (required)
#   GITLAB_API_URL - GitLab API base URL (default: https://gitlab.com/api/v4)
#

set -e

# Arguments
SOURCE_BRANCH="${1:?Error: source_branch required}"
TARGET_BRANCH="${2:-main}"
TITLE="${3:?Error: title required}"
DESCRIPTION="${4:-}"

# GitLab API URL
GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

# Get token from environment or settings file
get_token() {
    if [ -n "$GITLAB_PERSONAL_ACCESS_TOKEN" ]; then
        echo "$GITLAB_PERSONAL_ACCESS_TOKEN"
        return
    fi

    # Try reading from Claude settings
    local settings_file="$HOME/.claude/settings.json"
    if [ -f "$settings_file" ]; then
        local token
        token=$(cat "$settings_file" | grep -o '"GITLAB_PERSONAL_ACCESS_TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
        if [ -n "$token" ]; then
            echo "$token"
            return
        fi
    fi

    echo "Error: GITLAB_PERSONAL_ACCESS_TOKEN not found" >&2
    echo "Set it via environment variable or in ~/.claude/settings.json" >&2
    exit 1
}

# Extract project path from git remote URL
# Supports: git@gitlab.com:user/repo.git and https://gitlab.com/user/repo.git
extract_project_path() {
    local url="$1"
    echo "$url" | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's|\.git$||'
}

# URL encode project path (replace / with %2F)
url_encode_path() {
    echo "$1" | sed 's|/|%2F|g'
}

# Get numeric project ID from path
get_project_id() {
    local token="$1"
    local project_path="$2"
    local encoded_path
    encoded_path=$(url_encode_path "$project_path")

    curl -sf --header "PRIVATE-TOKEN: $token" \
        "${GITLAB_API_URL}/projects/${encoded_path}" | \
        grep -o '"id":[0-9]*' | head -1 | sed 's/"id"://'
}

# Main execution
main() {
    echo "=== GitLab Cross-Project MR Creator ===" >&2

    # Get token
    local token
    token=$(get_token)

    # Get remote URLs
    local origin_url upstream_url
    origin_url=$(git remote get-url origin 2>/dev/null || true)
    upstream_url=$(git remote get-url upstream 2>/dev/null || true)

    if [ -z "$origin_url" ]; then
        echo "Error: No 'origin' remote found" >&2
        exit 1
    fi

    if [ -z "$upstream_url" ]; then
        echo "Error: No 'upstream' remote found" >&2
        echo "This script is for fork scenarios only." >&2
        echo "Use GitLab MCP for same-project MRs." >&2
        exit 1
    fi

    # Extract project paths
    local origin_project upstream_project
    origin_project=$(extract_project_path "$origin_url")
    upstream_project=$(extract_project_path "$upstream_url")

    echo "Source (fork): $origin_project" >&2
    echo "Target (upstream): $upstream_project" >&2
    echo "Branch: $SOURCE_BRANCH -> $TARGET_BRANCH" >&2

    # Get source project ID (fork)
    echo "Getting source project ID..." >&2
    local source_project_id
    source_project_id=$(get_project_id "$token" "$origin_project")

    if [ -z "$source_project_id" ]; then
        echo "Error: Could not get project ID for $origin_project" >&2
        exit 1
    fi
    echo "Source project ID: $source_project_id" >&2

    # URL encode upstream project
    local upstream_encoded
    upstream_encoded=$(url_encode_path "$upstream_project")

    # Create MR
    echo "Creating Merge Request..." >&2

    local response
    response=$(curl -sf --request POST \
        --header "PRIVATE-TOKEN: $token" \
        --header "Content-Type: application/json" \
        --data "{
            \"source_branch\": \"$SOURCE_BRANCH\",
            \"target_branch\": \"$TARGET_BRANCH\",
            \"title\": \"$TITLE\",
            \"description\": \"$DESCRIPTION\",
            \"source_project_id\": $source_project_id
        }" \
        "${GITLAB_API_URL}/projects/${upstream_encoded}/merge_requests" 2>&1)

    # Check for errors
    if echo "$response" | grep -q '"error"'; then
        echo "Error creating MR:" >&2
        echo "$response" | grep -o '"message":"[^"]*"' >&2
        exit 1
    fi

    # Extract MR info
    local mr_iid mr_url
    mr_iid=$(echo "$response" | grep -o '"iid":[0-9]*' | head -1 | sed 's/"iid"://')
    mr_url=$(echo "$response" | grep -o '"web_url":"[^"]*"' | head -1 | sed 's/"web_url":"//' | sed 's/"$//')

    echo "" >&2
    echo "=== MR Created Successfully ===" >&2
    echo "MR: !$mr_iid" >&2
    echo "URL: $mr_url" >&2

    # Output JSON for programmatic use
    echo "{\"iid\": $mr_iid, \"url\": \"$mr_url\"}"
}

main "$@"
