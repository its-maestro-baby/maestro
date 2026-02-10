#!/usr/bin/env bash
# scan-contributors.sh v0.3.3 - Contributor scanner + gitignore validator
# Usage: ./scan-contributors.sh [dir] [--scan|--verify|--fix|--fix-all|--help]
set -euo pipefail

# Configurable via environment variables
ALLOWED_NAME="${SCAN_ALLOWED_NAME:-bennyblancobronx}"
ALLOWED_EMAIL="${SCAN_ALLOWED_EMAIL:-casket.iphone392@nizomail.com}"

# Disable colors if not a terminal
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

FOUND_ISSUES=0
SCAN_COUNT=0
GITIGNORE_ISSUES=0

show_help() {
    echo "Usage: ./scan-contributors.sh [dir] [--scan|--verify|--fix|--fix-all|--help]"
    echo "Env: SCAN_ALLOWED_NAME, SCAN_ALLOWED_EMAIL"
    exit 0
}

# Parse arguments
TARGET_DIR="${1:-.}"
MODE="${2:-both}"

[[ "$TARGET_DIR" == "--help" || "$MODE" == "--help" ]] && show_help

# Validate target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}ERROR:${NC} '$TARGET_DIR' is not a directory" >&2
    exit 1
fi

# Convert to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# Required .gitignore entries
REQUIRED_IGNORES=(
    ".claude/settings.json"
    ".claude/settings.local.json"
    ".claude/helpers/"
    ".claude/agents/"
    ".claude/commands/"
    ".claude-flow/"
    ".mcp.json"
    "CLAUDE.md"
)

# Dangerous patterns in .claude files
DANGEROUS_CLAUDE_PATTERNS=(
    "noreply@anthropic\.com"
    "ruv@ruv\.net"
    "@author[[:space:]]*:[[:space:]]*claude"
)

verify_gitignore() {
    local gitignore="$TARGET_DIR/.gitignore"
    echo -e "${BLUE}[GITIGNORE]${NC} Checking..."

    if [[ ! -f "$gitignore" ]]; then
        echo -e "${RED}[MISSING]${NC} No .gitignore!"
        GITIGNORE_ISSUES=$((GITIGNORE_ISSUES + 1))
        return
    fi

    local missing=()
    for pattern in "${REQUIRED_IGNORES[@]}"; do
        local found=false
        # Check exact match or wildcard version
        if grep -qE "^${pattern}$|^\*\*/${pattern}$|^${pattern%/}/?$" "$gitignore" 2>/dev/null; then
            found=true
        fi
        # Check if parent directory is ignored
        if [[ "$found" == "false" ]]; then
            local parent_dir
            parent_dir=$(dirname "$pattern")
            if [[ "$parent_dir" != "." ]]; then
                if grep -qE "^${parent_dir}/?$|^\*\*/${parent_dir}/?$" "$gitignore" 2>/dev/null; then
                    found=true
                fi
            fi
        fi
        [[ "$found" == "false" ]] && missing+=("$pattern")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "${GREEN}[OK]${NC} .gitignore complete"
    else
        for p in "${missing[@]}"; do
            echo -e "${RED}[MISSING]${NC} $p"
            GITIGNORE_ISSUES=$((GITIGNORE_ISSUES + 1))
        done
    fi

    # Scan unignored .claude files for dangerous content
    if [[ -d "$TARGET_DIR/.claude" ]]; then
        local is_valid_git=false
        git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1 && is_valid_git=true

        while IFS= read -r -d '' file; do
            [[ -z "$file" || ! -f "$file" ]] && continue

            local is_ignored=false
            if [[ "$is_valid_git" == "true" ]]; then
                git -C "$TARGET_DIR" check-ignore -q "$file" 2>/dev/null && is_ignored=true
            else
                if [[ -f "$gitignore" ]]; then
                    local relpath="${file#$TARGET_DIR/}"
                    local dirpath
                    dirpath=$(dirname "$relpath")
                    if grep -qE "^${relpath}$|^\*\*/${relpath}$|^${dirpath}/$|^\*\*/${dirpath}/$" "$gitignore" 2>/dev/null; then
                        is_ignored=true
                    fi
                fi
            fi

            if [[ "$is_ignored" == "false" ]]; then
                for pat in "${DANGEROUS_CLAUDE_PATTERNS[@]}"; do
                    if grep -qiE "$pat" "$file" 2>/dev/null; then
                        echo -e "${RED}[DANGER]${NC} $file: $pat"
                        GITIGNORE_ISSUES=$((GITIGNORE_ISSUES + 1))
                        break
                    fi
                done
            fi
        done < <(find "$TARGET_DIR/.claude" -type f \( -name "*.json" -o -name "*.sh" -o -name "*.md" \) -print0 2>/dev/null)
    fi
}

fix_gitignore() {
    local gitignore="$TARGET_DIR/.gitignore" added=0
    echo -e "${BLUE}[AUTO-FIX GITIGNORE]${NC}"
    [[ ! -f "$gitignore" ]] && { touch "$gitignore"; echo "Created .gitignore"; }
    grep -q "# Claude Code / AI tooling" "$gitignore" 2>/dev/null || echo -e "\n# Claude Code / AI tooling - DO NOT COMMIT" >> "$gitignore"
    for p in "${REQUIRED_IGNORES[@]}"; do
        grep -qE "^${p}$|^\*\*/${p}$" "$gitignore" 2>/dev/null || { echo "$p" >> "$gitignore"; echo -e "${GREEN}[ADDED]${NC} $p"; added=$((added + 1)); }
        grep -qE "^\*\*/${p}$" "$gitignore" 2>/dev/null || { echo "**/$p" >> "$gitignore"; added=$((added + 1)); }
    done
    [[ $added -eq 0 ]] && echo "No changes needed" || echo -e "${GREEN}Added $added entries${NC}"
    echo ""
}

# Contributor patterns
CRITICAL_PATTERNS=( 'co-author[[:space:]]*:' )
AI_CRITICAL_PATTERNS=(
    'generated[[:space:]]by[[:space:]]claude[[:space:]]code'
    'generated[[:space:]]by[[:space:]]gpt-[0-9]'
    'generated[[:space:]]by[[:space:]]copilot'
    'written[[:space:]]by[[:space:]]claude'
    'written[[:space:]]by[[:space:]]chatgpt'
    'written[[:space:]]by[[:space:]]gpt'
)

EMAIL_PATTERN='[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

log_issue() {
    local sev="$1" file="$2" ln="$3" pat="$4" content="$5"
    [[ "$sev" == "CRITICAL" ]] && echo -e "${RED}[CRITICAL]${NC} $file:$ln" || echo -e "${YELLOW}[WARNING]${NC} $file:$ln"
    echo -e "  Pattern: $pat\n  Content: ${content:0:100}\n"
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
}

should_skip_file() {
    local file="$1"
    local basename
    basename=$(basename "$file")

    # Skip lock files
    [[ "$basename" == "package-lock.json" ]] && return 0
    [[ "$basename" == "yarn.lock" ]] && return 0
    [[ "$basename" == "Cargo.lock" ]] && return 0

    # Skip toolbox scripts that contain pattern matching code
    [[ "$basename" == "scan-contributors.sh" ]] && return 0
    [[ "$basename" == "pre-push" && "$file" == *hooks/* ]] && return 0
    [[ "$basename" == "post-commit" && "$file" == *hooks/* ]] && return 0

    return 1
}

scan_file() {
    local file="$1"
    should_skip_file "$file" && return
    [[ -r "$file" ]] || return

    SCAN_COUNT=$((SCAN_COUNT + 1))

    # Skip binary files (check mime type for reliability)
    local mime
    mime=$(file --brief --mime-type "$file" 2>/dev/null || echo "unknown")
    [[ "$mime" != text/* && "$mime" != application/json && "$mime" != application/javascript && "$mime" != application/x-shellscript ]] && return

    # Critical patterns
    for pattern in "${CRITICAL_PATTERNS[@]}"; do
        while IFS=: read -r line_num content; do
            [[ -z "$line_num" ]] && continue
            # Skip if exactly matches allowed name/email (case-sensitive, exact)
            if echo "$content" | grep -qF "$ALLOWED_EMAIL"; then
                local other_emails
                other_emails=$(echo "$content" | grep -oE "$EMAIL_PATTERN" | grep -vF "$ALLOWED_EMAIL" || true)
                [[ -z "$other_emails" ]] && continue
            fi
            log_issue "CRITICAL" "$file" "$line_num" "$pattern" "$content"
        done < <(grep -niE "$pattern" "$file" 2>/dev/null || true)
    done

    # AI patterns
    for pattern in "${AI_CRITICAL_PATTERNS[@]}"; do
        while IFS=: read -r line_num content; do
            [[ -z "$line_num" ]] && continue
            # Skip detection/rule code
            echo "$content" | grep -qiE "(detect|check|scan|rule|pattern|grep|match|block|strip)" && continue
            # Skip AI feature descriptions (not attribution)
            echo "$content" | grep -qiE "ai-generated[[:space:]]+(topolog|model|content|image|text|data|response|output)" && continue
            echo "$content" | grep -qiE '"description".*ai-assisted' && continue
            log_issue "CRITICAL" "$file" "$line_num" "AI: $pattern" "$content"
        done < <(grep -niE "$pattern" "$file" 2>/dev/null || true)
    done

    # Unauthorized emails in author contexts
    while IFS=: read -r line_num content; do
        [[ -z "$line_num" ]] && continue
        local email
        email=$(echo "$content" | grep -oE "$EMAIL_PATTERN" | head -1)
        if [[ -n "$email" && "$email" != "$ALLOWED_EMAIL" ]]; then
            echo "$email" | grep -qiE "(example\.com|test\.com|localhost|noreply|users\.noreply\.github|company\.com)" && continue
            log_issue "WARNING" "$file" "$line_num" "Unauthorized email in author context" "$content"
        fi
    done < <(grep -niE "(^[[:space:]]*(author|by|contributor)[[:space:]]*[=:]|co-authored).*$EMAIL_PATTERN" "$file" 2>/dev/null || true)
}

scan_for_intruders() {
    echo -e "${BLUE}[INTRUDER SCAN]${NC}"
    echo "Scanning for unauthorized contributors..."
    echo ""

    pushd "$TARGET_DIR" >/dev/null || { echo "ERROR: Cannot cd to $TARGET_DIR" >&2; return 1; }

    if [[ -d ".git" ]]; then
        echo "Mode: Git-aware (tracked + untracked non-ignored files)"
        echo ""
        while IFS= read -r -d '' file; do
            [[ -z "$file" || ! -f "$file" ]] && continue
            scan_file "$file"
        done < <(git ls-files --cached --others --exclude-standard -z 2>/dev/null)

        echo "Scanning git history..."
        local unauth_authors
        unauth_authors=$(git log --all --format="%an <%ae>" 2>/dev/null | sort -u | grep -vF "$ALLOWED_NAME" | grep -v "^$" || true)
        if [[ -n "$unauth_authors" ]]; then
            echo -e "${RED}[GIT CRITICAL]${NC} Unauthorized authors in history:"
            echo "$unauth_authors"
            echo ""
            FOUND_ISSUES=$((FOUND_ISSUES + 1))
        fi
    else
        echo "Mode: Full scan (no git repo)"
        echo ""
        while IFS= read -r -d '' file; do
            scan_file "$file"
        done < <(find . -type f \( -name "*.md" -o -name "*.txt" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" \) -not -path "*/.git/*" -not -path "*/node_modules/*" -print0 2>/dev/null)
    fi

    popd >/dev/null || true
    echo ""
}

echo "Contributor Scanner v0.3.3 | Target: $TARGET_DIR | Allowed: $ALLOWED_NAME"

fix_all_intruders() {
    echo -e "${BLUE}[PURGE ALL GHOSTS]${NC}"
    echo "Stripping ALL ghost contributors. No exceptions."
    echo ""

    local fixed=0
    pushd "$TARGET_DIR" >/dev/null || { echo "ERROR: Cannot cd to $TARGET_DIR" >&2; return 1; }

    while IFS= read -r -d '' file; do
        [[ -z "$file" || ! -f "$file" ]] && continue
        should_skip_file "$file" && continue

        # Skip binary files
        local mime
        mime=$(file --brief --mime-type "$file" 2>/dev/null || echo "unknown")
        [[ "$mime" != text/* && "$mime" != application/json && "$mime" != application/x-shellscript ]] && continue

        local changed=false

        # Split pattern into variables so hook sed patterns cannot match this guard line
        local _ca_pfx="co-authored" _ca_sfx="-by"
        if grep -qiE "${_ca_pfx}${_ca_sfx}" "$file" 2>/dev/null; then
            if [[ "$OSTYPE" == darwin* ]]; then
                sed -i '' -e '/[Cc]o-[Aa]uthored-[Bb]y/d' "$file" 2>/dev/null || true
            else
                sed -i -e '/[Cc]o-[Aa]uthored-[Bb]y/d' "$file" 2>/dev/null || true
            fi
            changed=true
        fi

        if grep -qiE "generated (by|with)" "$file" 2>/dev/null; then
            if [[ "$OSTYPE" == darwin* ]]; then
                sed -i '' -e '/[Gg]enerated by/d' -e '/[Gg]enerated with/d' "$file" 2>/dev/null || true
            else
                sed -i -e '/[Gg]enerated by/d' -e '/[Gg]enerated with/d' "$file" 2>/dev/null || true
            fi
            changed=true
        fi

        # Strip author/contributor lines with external emails
        if grep -qiE "(author|contributor|written by|created by).*@" "$file" 2>/dev/null; then
            if ! grep -qF "$ALLOWED_EMAIL" "$file" 2>/dev/null; then
                if [[ "$OSTYPE" == darwin* ]]; then
                    sed -i '' -e '/[Aa]uthor.*@/d' -e '/[Cc]ontributor.*@/d' -e '/[Ww]ritten [Bb]y.*@/d' -e '/[Cc]reated [Bb]y.*@/d' "$file" 2>/dev/null || true
                else
                    sed -i -e '/[Aa]uthor.*@/d' -e '/[Cc]ontributor.*@/d' -e '/[Ww]ritten [Bb]y.*@/d' -e '/[Cc]reated [Bb]y.*@/d' "$file" 2>/dev/null || true
                fi
                changed=true
            fi
        fi

        if [[ "$changed" == "true" ]]; then
            echo -e "${GREEN}[PURGED]${NC} $file"
            fixed=$((fixed + 1))
        fi
    done < <(git ls-files -z 2>/dev/null || find . -type f -not -path '*/.git/*' -print0)

    popd >/dev/null || true
    echo ""
    echo -e "${GREEN}Purged $fixed file(s)${NC}"
    echo ""
}

case "$MODE" in
    --verify)
        verify_gitignore
        ;;
    --scan)
        scan_for_intruders
        ;;
    --fix)
        fix_gitignore
        verify_gitignore
        ;;
    --fix-all)
        fix_gitignore
        fix_all_intruders
        echo -e "${GREEN}All issues auto-fixed.${NC}"
        exit 0
        ;;
    --help)
        show_help
        ;;
    both|*)
        verify_gitignore
        scan_for_intruders
        ;;
esac

# Summary
echo "=========================================="
TOTAL_ISSUES=$((FOUND_ISSUES + GITIGNORE_ISSUES))

if [[ "$MODE" != "--verify" ]]; then
    echo "Files scanned: $SCAN_COUNT"
fi
echo "Intruder issues: $FOUND_ISSUES"
echo "Gitignore issues: $GITIGNORE_ISSUES"
echo ""

if [[ $TOTAL_ISSUES -eq 0 ]]; then
    echo -e "${GREEN}Status: CLEAN - No issues found${NC}"
    exit 0
else
    echo -e "${RED}Status: $TOTAL_ISSUES issue(s) found${NC}"
    if [[ $GITIGNORE_ISSUES -gt 0 ]]; then
        echo ""
        echo "Run with --fix to auto-add missing gitignore entries"
    fi
    exit 1
fi
