#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop for Claude Code
# Usage: ./ralph.sh [max_iterations]
#
# Requires: Claude Code CLI
#
# Safety features:
# - Rate limiting: MAX_CALLS_PER_HOUR (default: 100)
# - Circuit breaker: MAX_NO_PROGRESS (default: 3 iterations without progress)
#
# Exit codes:
# - 0: All tasks completed successfully
# - 1: Max iterations reached without completion
# - 2: Circuit breaker triggered (no progress)

set -e

# Add common Claude CLI locations to PATH
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

MAX_ITERATIONS=${1:-10}
MAX_CALLS_PER_HOUR=${MAX_CALLS_PER_HOUR:-100}
MAX_NO_PROGRESS=${MAX_NO_PROGRESS:-3}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PRD_FILE="$PROJECT_DIR/prd.json"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"
ARCHIVE_DIR="$PROJECT_DIR/archive"
LAST_BRANCH_FILE="$PROJECT_DIR/.last-branch"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Rate limiting setup
HOUR_START=$(date +%H)
CALL_COUNT=0

# Circuit breaker setup
NO_PROGRESS_COUNT=0
LAST_PRD_HASH=""

echo ""
echo "Starting Ralph (Claude Code) - Max iterations: $MAX_ITERATIONS"
echo "Project directory: $PROJECT_DIR"
echo "Rate limit: $MAX_CALLS_PER_HOUR calls/hour | Circuit breaker: $MAX_NO_PROGRESS no-progress loops"

# Check if Claude Code CLI is installed
if ! command -v claude &> /dev/null; then
  echo "Error: Claude Code CLI not found."
  echo "Install with: npm install -g @anthropic-ai/claude-code"
  echo "Or check that ~/.local/bin is in your PATH"
  exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS (Claude Code)"
  echo "═══════════════════════════════════════════════════════"

  # Rate limiting check
  CURRENT_HOUR=$(date +%H)
  if [ "$CURRENT_HOUR" != "$HOUR_START" ]; then
    HOUR_START=$CURRENT_HOUR
    CALL_COUNT=0
    echo "Rate limit reset for new hour"
  fi

  if [ "$CALL_COUNT" -ge "$MAX_CALLS_PER_HOUR" ]; then
    echo "Rate limit reached ($MAX_CALLS_PER_HOUR calls/hour). Waiting 60s..."
    sleep 60
    continue
  fi

  CALL_COUNT=$((CALL_COUNT + 1))
  echo "API calls this hour: $CALL_COUNT/$MAX_CALLS_PER_HOUR"

  # Build full prompt with iteration context prepended
  FULL_PROMPT="[Ralph Iteration $i of $MAX_ITERATIONS]
[Working directory: $(pwd)]

$(cat "$SCRIPT_DIR/prompt.md")"

  # Execute Claude Code with stdin approach
  OUTPUT=$(echo "$FULL_PROMPT" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Ralph completed all tasks!"
    echo "  Completed at iteration $i of $MAX_ITERATIONS"
    echo "═══════════════════════════════════════════════════════"
    exit 0
  fi

  # Circuit breaker: check for progress by comparing prd.json hash
  CURRENT_PRD_HASH=$(md5sum "$PRD_FILE" 2>/dev/null | cut -d' ' -f1 || md5 -q "$PRD_FILE" 2>/dev/null)
  if [ -n "$LAST_PRD_HASH" ] && [ "$CURRENT_PRD_HASH" = "$LAST_PRD_HASH" ]; then
    NO_PROGRESS_COUNT=$((NO_PROGRESS_COUNT + 1))
    echo ""
    echo "Warning: No progress detected ($NO_PROGRESS_COUNT/$MAX_NO_PROGRESS)"
    if [ "$NO_PROGRESS_COUNT" -ge "$MAX_NO_PROGRESS" ]; then
      echo ""
      echo "═══════════════════════════════════════════════════════"
      echo "  Circuit breaker triggered!"
      echo "  $MAX_NO_PROGRESS consecutive iterations without progress"
      echo "  Check $PROGRESS_FILE and $PRD_FILE for status."
      echo "═══════════════════════════════════════════════════════"
      exit 2
    fi
  else
    NO_PROGRESS_COUNT=0
  fi
  LAST_PRD_HASH=$CURRENT_PRD_HASH

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Ralph reached max iterations ($MAX_ITERATIONS)"
echo "  without completing all tasks."
echo "  Check $PROGRESS_FILE for status."
echo "═══════════════════════════════════════════════════════"
exit 1
