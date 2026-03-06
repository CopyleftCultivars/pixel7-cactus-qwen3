#!/usr/bin/env bash
# upload_to_hf.sh - Zip and upload the converted cactus model to HuggingFace Hub.
#
# Usage:
#   bash finetune/upload_to_hf.sh --repo YOUR_HF_USERNAME/your-repo-name
#
# Prerequisites:
#   conda activate cactus-convert  (or any env with huggingface_hub installed)
#   huggingface-cli login          (run once to authenticate)
#
# Options:
#   --model-dir DIR    Path to cact-model directory (default: finetune/outputs/cact-model)
#   --repo REPO        HuggingFace repo in format username/repo-name (required)
#   --filename NAME    Zip filename to upload (default: qwen3-nf-finetuned.zip)
#   -h, --help         Print this help and exit

set -euo pipefail

MODEL_DIR="finetune/outputs/cact-model"
HF_REPO=""
ZIP_FILENAME="qwen3-nf-finetuned.zip"
TMP_ZIP="/tmp/$ZIP_FILENAME"

usage() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model-dir) MODEL_DIR="$2"; shift 2 ;;
        --repo)      HF_REPO="$2";   shift 2 ;;
        --filename)  ZIP_FILENAME="$2"; TMP_ZIP="/tmp/$ZIP_FILENAME"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$HF_REPO" ]]; then
    echo "ERROR: --repo is required (e.g. --repo yourname/qwen3-nf-finetuned)" >&2
    exit 1
fi

if [[ ! -d "$MODEL_DIR" ]]; then
    echo "ERROR: Model directory not found: $MODEL_DIR" >&2
    exit 1
fi

# ── Zip the model directory (flat — contents go to zip root) ──────────────────
echo "==> Zipping $MODEL_DIR → $TMP_ZIP ..."
# Zip contents of MODEL_DIR directly (no parent folder in zip)
(cd "$MODEL_DIR" && zip -r "$TMP_ZIP" .)

ZIP_SIZE_MB=$(( $(stat -c%s "$TMP_ZIP") / 1048576 ))
echo "==> Zip size: ${ZIP_SIZE_MB} MB"
echo ""

# ── Upload to HuggingFace Hub ─────────────────────────────────────────────────
echo "==> Creating/uploading to HuggingFace repo: $HF_REPO ..."
python3 - <<PYEOF
from huggingface_hub import HfApi, create_repo
import sys

api = HfApi()
repo_id = "$HF_REPO"
filename = "$ZIP_FILENAME"
local_path = "$TMP_ZIP"

try:
    create_repo(repo_id, repo_type="model", exist_ok=True)
    print(f"  Repo: https://huggingface.co/{repo_id}")
except Exception as e:
    print(f"  Warning: repo creation: {e}", file=sys.stderr)

print(f"  Uploading {filename} ...")
url = api.upload_file(
    path_or_fileobj=local_path,
    path_in_repo=filename,
    repo_id=repo_id,
    repo_type="model",
)
print(f"  Uploaded: {url}")

download_url = f"https://huggingface.co/{repo_id}/resolve/main/{filename}"
print("")
print("==> Download URL for Flutter app:")
print(f"    {download_url}")
print("")
print("==> Set this in natural_farming_chat/lib/services/model_service.dart:")
print(f"    static const String _modelDownloadUrl = '{download_url}';")
PYEOF

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "$TMP_ZIP"
echo "==> Upload complete. Update _modelDownloadUrl in model_service.dart and rebuild the app."
