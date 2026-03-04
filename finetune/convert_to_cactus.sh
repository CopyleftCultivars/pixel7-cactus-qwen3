#!/usr/bin/env bash
# convert_to_cactus.sh - Convert merged HuggingFace model to Cactus .cact format.
#
# Clones cactus-compute/cactus (if not already present), installs its conversion
# dependencies, then runs tools/convert_hf.py on the merged model.
#
# Usage:
#   bash finetune/convert_to_cactus.sh [OPTIONS]
#
# Options:
#   --merged-model DIR    Path to merged HuggingFace model (default: finetune/outputs/merged-model)
#   --output DIR          Output directory for .cact weights  (default: finetune/outputs/cact-model)
#   --precision PREC      INT4 | INT8 | FP16               (default: INT8)
#   --cactus-dir DIR      Where to clone/find the cactus repo (default: finetune/cactus-sdk)
#   -h, --help            Print this help and exit
#
# Example:
#   bash finetune/convert_to_cactus.sh --precision INT8

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
MERGED_MODEL="finetune/outputs/merged-model"
OUTPUT_DIR="finetune/outputs/cact-model"
PRECISION="INT8"
CACTUS_DIR="finetune/cactus-sdk"

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --merged-model) MERGED_MODEL="$2"; shift 2 ;;
        --output)       OUTPUT_DIR="$2";   shift 2 ;;
        --precision)    PRECISION="$2";    shift 2 ;;
        --cactus-dir)   CACTUS_DIR="$2";  shift 2 ;;
        -h|--help)      usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Validate precision ─────────────────────────────────────────────────────────
case "$PRECISION" in
    INT4|INT8|FP16) ;;
    *) echo "ERROR: --precision must be INT4, INT8, or FP16 (got: $PRECISION)" >&2; exit 1 ;;
esac

# ── Validate merged model exists ───────────────────────────────────────────────
if [[ ! -d "$MERGED_MODEL" ]]; then
    echo "ERROR: Merged model directory not found: $MERGED_MODEL" >&2
    echo "       Run finetune/merge_adapter.py first." >&2
    exit 1
fi

if ! ls "$MERGED_MODEL"/*.safetensors &>/dev/null; then
    echo "ERROR: No .safetensors files found in $MERGED_MODEL" >&2
    echo "       Ensure merge_adapter.py completed successfully." >&2
    exit 1
fi

echo "==> Merged model : $MERGED_MODEL"
echo "==> Output dir   : $OUTPUT_DIR"
echo "==> Precision    : $PRECISION"
echo "==> Cactus SDK   : $CACTUS_DIR"
echo ""

# ── Clone or update cactus-compute/cactus ─────────────────────────────────────
if [[ -d "$CACTUS_DIR/.git" ]]; then
    echo "==> Cactus repo already present at $CACTUS_DIR — pulling latest ..."
    git -C "$CACTUS_DIR" pull --ff-only
else
    echo "==> Cloning cactus-compute/cactus → $CACTUS_DIR ..."
    git clone --depth=1 https://github.com/cactus-compute/cactus.git "$CACTUS_DIR"
fi
echo ""

# ── Install conversion dependencies ───────────────────────────────────────────
REQUIREMENTS="$CACTUS_DIR/tools/requirements.txt"
if [[ -f "$REQUIREMENTS" ]]; then
    echo "==> Installing conversion dependencies from $REQUIREMENTS ..."
    pip install --quiet -r "$REQUIREMENTS"
else
    echo "WARNING: $REQUIREMENTS not found — skipping dependency install." >&2
fi
echo ""

# ── Run conversion ─────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

CONVERT_SCRIPT="$CACTUS_DIR/tools/convert_hf.py"
if [[ ! -f "$CONVERT_SCRIPT" ]]; then
    echo "ERROR: Conversion script not found: $CONVERT_SCRIPT" >&2
    echo "       The cactus-compute/cactus repository structure may have changed." >&2
    exit 1
fi

echo "==> Running Cactus conversion ..."
echo "    python3 $CONVERT_SCRIPT $MERGED_MODEL $OUTPUT_DIR --precision $PRECISION"
echo ""

python3 "$CONVERT_SCRIPT" \
    "$MERGED_MODEL" \
    "$OUTPUT_DIR" \
    --precision "$PRECISION"

# ── Verify output ──────────────────────────────────────────────────────────────
CACT_FILES=()
while IFS= read -r -d '' f; do
    CACT_FILES+=("$f")
done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "*.cact" -print0 2>/dev/null)
if [[ ${#CACT_FILES[@]} -eq 0 ]]; then
    echo "" >&2
    echo "WARNING: No .cact files found in $OUTPUT_DIR after conversion." >&2
    echo "         Check the output above for errors from convert_hf.py." >&2
    exit 1
fi

echo ""
echo "==> Conversion complete."
for f in "${CACT_FILES[@]}"; do
    size_mb=$(( $(stat -c%s "$f") / 1048576 ))
    echo "    $f  (${size_mb} MB)"
done

echo ""
echo "==> Next step: deploy $OUTPUT_DIR to your Flutter app via Cactus SDK."
echo "    See finetune_plan.md §4 for deployment options (bundle or HF download)."
