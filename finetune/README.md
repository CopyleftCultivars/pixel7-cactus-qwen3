# Qwen3-0.6B Fine-Tuning Pipeline

QLoRA fine-tuning pipeline for [Qwen/Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B) targeting on-device deployment via the Cactus SDK on a Pixel 7.

See [finetune_plan.md](../finetune_plan.md) for full methodology, hyperparameters, and deployment details.

## Directory Structure

```
finetune/
├── environment.yml        # Conda environment definition
├── README.md              # This file
├── prepare_dataset.py     # Convert source JSON → JSONL training pairs
├── train.py               # QLoRA fine-tuning via Unsloth + TRL
├── merge_adapter.py       # Merge LoRA adapter into base model
├── convert_cact.py        # Convert merged model to Cactus .cact format
├── data/                  # Processed JSONL datasets (gitignored)
├── weights/               # Downloaded base model weights (gitignored)
└── outputs/               # Training checkpoints and final models (gitignored)
```

## Setup

### Prerequisites

- [Miniconda](https://docs.conda.io/en/latest/miniconda.html) or Anaconda
- CUDA 12.1+ (for GPU training; adjust torch index URL in environment.yml if needed)
- 8+ GB VRAM recommended for QLoRA on Qwen3-0.6B

### Create the Conda Environment

```bash
conda env create -f finetune/environment.yml
conda activate qwen3-finetune
```

### Verify Installation

```python
python -c "import torch; print(torch.cuda.is_available(), torch.version.cuda)"
python -c "from unsloth import FastLanguageModel; print('unsloth ok')"
python -c "from peft import get_peft_model; print('peft ok')"
```

## Pipeline Steps

### 1. Prepare Dataset

```bash
conda activate qwen3-finetune
python finetune/prepare_dataset.py \
  --input NF_Recipes.json \
  --output finetune/data/train.jsonl \
  --split 0.9
```

Produces JSONL files with `{"instruction": "...", "output": "..."}` pairs.

### 2. Fine-Tune (QLoRA)

```bash
conda activate qwen3-finetune
python finetune/train.py \
  --model Qwen/Qwen3-0.6B \
  --dataset finetune/data/train.jsonl \
  --output finetune/outputs/lora-adapter \
  --epochs 3 \
  --rank 32
```

Saves a LoRA adapter checkpoint to `finetune/outputs/lora-adapter/`.

### 3. Merge Adapter

```bash
conda activate qwen3-finetune
python finetune/merge_adapter.py \
  --base Qwen/Qwen3-0.6B \
  --adapter finetune/outputs/lora-adapter \
  --output finetune/outputs/merged-model
```

### 4. Convert to Cactus Format

```bash
conda activate qwen3-finetune
python finetune/convert_cact.py \
  --input finetune/outputs/merged-model \
  --output finetune/outputs/qwen3-0.6b-finetuned.cact \
  --precision INT8
```

## Compute Requirements

| Method | VRAM | Time (10K samples) | Cost estimate |
|---|---|---|---|
| QLoRA (recommended) | 4–8 GB | 30 min – 2 hr | < $2 |
| Full fine-tune | ~10 GB | 1–4 hr | < $5 |

Free options: Google Colab T4 (16 GB VRAM), Kaggle (2× T4).

## Notes

- `weights/` and `outputs/` are gitignored — download/generate locally
- The `.cact` format is Cactus proprietary; conversion requires the Cactus tools (`tools/convert_hf.py`) from the Cactus SDK repo
- For Spanish domain fine-tuning, see the two-stage approach in `finetune_plan.md` §2.1
