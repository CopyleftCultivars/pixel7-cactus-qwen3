#!/usr/bin/env bash
# convert_to_cactus.sh - Convert merged HuggingFace model to a runnable Cactus bundle.
#
# Clones cactus-compute/cactus (if not already present), uses the official cactus
# Python package, then runs the official cactus CLI on the merged model. The
# output includes CQ weights and runtime graph components.
#
# Usage:
#   bash conversion/convert_to_cactus.sh [OPTIONS]
#
# Options:
#   --merged-model DIR    Path to merged HuggingFace model (default: models/merged-model)
#   --output DIR          Output directory for the bundle (default: models/cactus-model)
#   --bits N              Quantization bits: 1 | 2 | 3 | 4 (default: 4)
#   --cache-context-length N  KV-cache length for mobile inference (default: 2048)
#   --cactus-dir DIR      Where to clone/find the cactus repo (default: conversion/cactus-sdk)
#   -h, --help            Print this help and exit
#
# Example:
#   bash conversion/convert_to_cactus.sh --bits 4 --cache-context-length 2048

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
MERGED_MODEL="models/merged-model"
OUTPUT_DIR="models/cactus-model"
BITS="4"
CACHE_CONTEXT_LENGTH="2048"
CACTUS_DIR="conversion/cactus-sdk"

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
        --cache-context-length) CACHE_CONTEXT_LENGTH="$2"; shift 2 ;;
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
    echo "       Pass a completed Hugging Face checkpoint with --merged-model." >&2
    exit 1
fi

if ! ls "$MERGED_MODEL"/*.safetensors &>/dev/null; then
    echo "ERROR: No .safetensors files found in $MERGED_MODEL" >&2
    echo "       Ensure the merged checkpoint is complete and contains safetensors files." >&2
    exit 1
fi

echo "==> Merged model  : $MERGED_MODEL"
echo "==> Output dir    : $OUTPUT_DIR"
echo "==> Bits          : $BITS"
echo "==> Cache length  : $CACHE_CONTEXT_LENGTH"
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

# ── Resolve the official cactus CLI from its venv ─────────────────────────────
VENV_PYTHON="$CACTUS_DIR/venv/bin/python"
CACTUS_BIN="$CACTUS_DIR/venv/bin/cactus"

if [[ ! -f "$VENV_PYTHON" || ! -x "$CACTUS_BIN" ]]; then
    echo "ERROR: Cactus venv/CLI not found at $CACTUS_DIR." >&2
    echo "       Run 'source $CACTUS_DIR/setup' to initialise the SDK venv." >&2
    exit 1
fi
echo ""

# ── Run conversion ─────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

echo "==> Running official Cactus conversion (weights + runtime graph) ..."
echo "    $CACTUS_BIN convert $MERGED_MODEL $OUTPUT_DIR --bits $BITS --reconvert"
echo ""

"$CACTUS_BIN" convert \
    "$MERGED_MODEL" \
    "$OUTPUT_DIR" \
    --bits "$BITS" \
    --reconvert \
    --artifact-dir "$OUTPUT_DIR" \
    --cache-context-length "$CACHE_CONTEXT_LENGTH" \
    --local-files-only

# ── Verify output ──────────────────────────────────────────────────────────────
OUTPUT_FILES=()
while IFS= read -r -d '' f; do
    OUTPUT_FILES+=("$f")
done < <(find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.weights" -o -name "*.cact" -o -name "config.txt" \) -print0 2>/dev/null)

if [[ ${#OUTPUT_FILES[@]} -eq 0 || ! -f "$OUTPUT_DIR/components/manifest.json" ]]; then
    echo "" >&2
    echo "WARNING: No converted weight files found in $OUTPUT_DIR after conversion." >&2
    echo "         Expected CQ weights and components/manifest.json." >&2
    exit 1
fi

echo ""
echo "==> Conversion complete. Output files:"
for f in "${OUTPUT_FILES[@]}"; do
    size_mb=$(( $(stat -c%s "$f") / 1048576 ))
    echo "    $f  (${size_mb} MB)"
done

echo ""
echo "==> Next step: upload $OUTPUT_DIR to HuggingFace via conversion/upload_to_hf.sh"
echo "    or deploy directly to your Flutter app via the Cactus SDK."
