#!/usr/bin/env bash
# convert_to_cactus.sh - Convert merged HuggingFace model to Cactus weights format.
#
# Clones cactus-compute/cactus (if not already present), installs the cactus
# Python package, then runs the cactus.convert CLI on the merged model.
#
# Usage:
#   bash finetune/convert_to_cactus.sh [OPTIONS]
#
# Options:
#   --merged-model DIR    Path to merged HuggingFace model (default: finetune/outputs/merged-model)
#   --output DIR          Output directory for converted weights (default: finetune/outputs/cact-model)
#   --bits N              Quantization bits: 1 | 2 | 3 | 4 (default: 4)
#   --model-family FAM    Model family override, e.g. gemma4 | qwen | auto (default: auto)
#   --cactus-dir DIR      Where to clone/find the cactus repo (default: finetune/cactus-sdk)
#   -h, --help            Print this help and exit
#
# Example:
#   bash finetune/convert_to_cactus.sh --bits 4 --model-family gemma4

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
MERGED_MODEL="finetune/outputs/merged-model"
OUTPUT_DIR="finetune/outputs/cact-model"
BITS="4"
MODEL_FAMILY="auto"
CACTUS_DIR="finetune/cactus-sdk"

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --merged-model) MERGED_MODEL="$2";  shift 2 ;;
        --output)       OUTPUT_DIR="$2";    shift 2 ;;
        --bits)         BITS="$2";          shift 2 ;;
        --model-family) MODEL_FAMILY="$2";  shift 2 ;;
        --cactus-dir)   CACTUS_DIR="$2";   shift 2 ;;
        -h|--help)      usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Validate bits ──────────────────────────────────────────────────────────────
case "$BITS" in
    1|2|3|4) ;;
    *) echo "ERROR: --bits must be 1, 2, 3, or 4 (got: $BITS)" >&2; exit 1 ;;
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

echo "==> Merged model  : $MERGED_MODEL"
echo "==> Output dir    : $OUTPUT_DIR"
echo "==> Bits          : $BITS"
echo "==> Cactus SDK    : $CACTUS_DIR"
echo ""

# ── Clone or update cactus-compute/cactus ─────────────────────────────────────
if [[ -d "$CACTUS_DIR/.git" ]]; then
    echo "==> Cactus repo already present at $CACTUS_DIR — pulling latest ..."
    git -C "$CACTUS_DIR" stash 2>/dev/null || true
    git -C "$CACTUS_DIR" pull --ff-only
else
    echo "==> Cloning cactus-compute/cactus → $CACTUS_DIR ..."
    git clone --depth=1 https://github.com/cactus-compute/cactus.git "$CACTUS_DIR"
fi
echo ""

# ── Resolve Python from cactus-sdk venv (has torch + transformers + cactus) ───
VENV_PYTHON="$CACTUS_DIR/venv/bin/python"
VENV_PIP="$CACTUS_DIR/venv/bin/pip"
PYTHON_PKG="$CACTUS_DIR/python"

if [[ -f "$VENV_PYTHON" ]]; then
    echo "==> Using cactus-sdk venv Python: $VENV_PYTHON"
    PYTHON="$VENV_PYTHON"
    PIP="$VENV_PIP"
elif [[ -f "$PYTHON_PKG/pyproject.toml" ]]; then
    echo "==> cactus-sdk venv not found — installing into system Python ..."
    echo "    Run 'source $CACTUS_DIR/setup' to create the venv for future runs."
    PYTHON="python3"
    PIP="pip3"
    "$PIP" install --quiet -e "$PYTHON_PKG"
else
    echo "ERROR: Neither $VENV_PYTHON nor $PYTHON_PKG/pyproject.toml found." >&2
    echo "       Run 'source $CACTUS_DIR/setup' to initialise the SDK venv." >&2
    exit 1
fi
echo ""

# ── Run conversion ─────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

echo "==> Running Cactus weight quantizer (CPU-only) ..."
echo "    $PYTHON -m cactus.convert convert --model $MERGED_MODEL --out $OUTPUT_DIR --bits $BITS --force"
echo ""

# Use cactus.convert.cli directly — the top-level 'cactus convert' transpiler
# tries to build a native ARM engine which fails on x86_64.
CUDA_VISIBLE_DEVICES="" "$PYTHON" -c "
from cactus.convert.cli import main
main()
" convert \
    --model "$MERGED_MODEL" \
    --out "$OUTPUT_DIR" \
    --bits "$BITS" \
    --force

# ── Verify output ──────────────────────────────────────────────────────────────
OUTPUT_FILES=()
while IFS= read -r -d '' f; do
    OUTPUT_FILES+=("$f")
done < <(find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.weights" -o -name "*.cact" -o -name "config.txt" \) -print0 2>/dev/null)

if [[ ${#OUTPUT_FILES[@]} -eq 0 ]]; then
    echo "" >&2
    echo "WARNING: No converted weight files found in $OUTPUT_DIR after conversion." >&2
    echo "         Check the output above for errors from cactus.convert." >&2
    exit 1
fi

echo ""
echo "==> Conversion complete. Output files:"
for f in "${OUTPUT_FILES[@]}"; do
    size_mb=$(( $(stat -c%s "$f") / 1048576 ))
    echo "    $f  (${size_mb} MB)"
done

echo ""
echo "==> Next step: upload $OUTPUT_DIR to HuggingFace via finetune/upload_to_hf.sh"
echo "    or deploy directly to your Flutter app via the Cactus SDK."
