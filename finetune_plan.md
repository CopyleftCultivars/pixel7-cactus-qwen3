# Qwen3-0.6B Fine-Tuning & Cactus Deployment Workflow

## Target Device & Stack

- **Device:** Google Pixel 7
- **Inference Engine:** Cactus Compute v1.7+
- **Model Format:** Cactus proprietary `.cact` format
- **App Framework:** Flutter (via `cactus` Dart package)
- **Base Model:** [Qwen/Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B) (Apache 2.0)

---

## 1. Model Comparison: Official Qwen vs Cactus Version

### Qwen/Qwen3-0.6B (Official)

The official release from Alibaba in standard HuggingFace safetensors format. This is the model used for fine-tuning.

| Property | Value |
|---|---|
| Parameters (total) | 0.6B |
| Parameters (non-embedding) | 0.44B |
| Layers | 28 |
| Attention Heads (Q / KV) | 16 / 8 (GQA) |
| Context Length | 32,768 tokens |
| Training Data | ~36 trillion tokens, 119 languages |
| Format | Safetensors (PyTorch-compatible) |
| License | Apache 2.0 |

Supports hybrid thinking/non-thinking mode switching, agentic tool calling, and multilingual generation including Spanish.

### Cactus-Compute/Qwen3-0.6B (Converted)

A pre-converted version of the same underlying model, produced via Cactus's conversion pipeline:

```bash
python3 tools/convert_hf.py Qwen/Qwen3-0.6B weights/qwen3-600m/ --precision INT8
```

The Cactus version uses the proprietary `.cact` format optimized for battery-efficient inference and minimal RAM usage via zero-copy memory mapping. It is not a different model architecturally — it is the same weights restructured for Cactus's custom ARM SIMD kernels, KV-cache quantization, and chunked prefill pipeline.

### Key Difference Summary

| Aspect | Qwen/Qwen3-0.6B | Cactus-Compute/Qwen3-0.6B |
|---|---|---|
| Format | HuggingFace safetensors | Cactus `.cact` (proprietary) |
| Purpose | Training / fine-tuning / general inference | On-device mobile inference |
| Quantization | Full precision (BF16/FP16) | INT8 (applied during conversion) |
| Can be fine-tuned directly | Yes | No |
| Runs on Pixel 7 via Cactus | No (needs conversion) | Yes |

---

## 2. Fine-Tuning Process

### 2.1 Dataset Preparation

Structure your data as instruction-response pairs in JSONL format:

```json
{"instruction": "Your prompt or question", "output": "Expected model response"}
```

For domain-specific fine-tuning (following the CROP paper's methodology), consider a two-stage approach:

1. **Stage 1 — General Spanish instruction tuning:** Use an existing Spanish instruction dataset (e.g., Alpaca-ES) or generate synthetic Spanish Q&A data to strengthen the model's Spanish instruction-following ability.
2. **Stage 2 — Domain-specific tuning:** Fine-tune on your custom domain dataset in Spanish, built from domain source material using an LLM-assisted generation pipeline with human filtering.

The CROP paper (NeurIPS 2024) demonstrated an average 29% accuracy improvement on their benchmark when fine-tuning 7B/8B models with ~210K single-turn dialogues, and an additional 9.2% improvement from the two-stage approach over single-stage. For a 0.6B model, expect more modest gains but the methodology remains sound.

### 2.2 Fine-Tuning Method: QLoRA (Recommended)

QLoRA (Quantized Low-Rank Adaptation) loads the base model in 4-bit precision and trains small adapter matrices in higher precision. This dramatically reduces memory requirements while preserving near full fine-tuning quality.

**Recommended tooling (pick one):**

- **Unsloth** — Free notebooks, 2x faster training, 70% less VRAM. Explicitly supports Qwen3-0.6B. Colab/Kaggle compatible.
- **LLaMA Factory** — Supports 16-bit full-tuning, freeze-tuning, LoRA, and 2–8-bit QLoRA. Includes FlashAttention-2 integration and Unsloth backend.
- **HuggingFace PEFT + bitsandbytes** — Standard library approach with `transformers`, `peft`, and `bitsandbytes` for 4-bit loading.

### 2.3 Compute Requirements for Fine-Tuning

#### QLoRA on Qwen3-0.6B

| Resource | Requirement |
|---|---|
| VRAM | 4–8 GB |
| Suitable GPUs | Google Colab T4 (free, 16GB), RTX 3060 12GB, RTX 4060 Ti 16GB, RTX 4090 24GB |
| Training time (10K–50K samples) | 30 min – 2 hours |
| Cloud cost estimate | < $1–2 total (RTX 4090 at ~$0.40–$0.80/hr) |

#### Full Fine-Tuning on Qwen3-0.6B

| Resource | Requirement |
|---|---|
| VRAM | ~10 GB (rule of thumb: ~16 GB per 1B params) |
| Suitable GPUs | RTX 3060 12GB, RTX 4060 Ti 16GB, any 12GB+ card |
| Training time (10K–50K samples) | 1–4 hours |
| Cloud cost estimate | < $2–5 total |

#### Two-Stage Fine-Tuning (CROP-Style, Spanish)

| Stage | Dataset Size | Additional Cost |
|---|---|---|
| Stage 1: Spanish instruction tuning | 10K–50K general Spanish instruction pairs | Same as above (another training run) |
| Stage 2: Domain-specific tuning | 5K–50K+ domain Q&A pairs | Same as above (another training run) |
| **Total compute cost** | — | **< $5–10 for both stages** |

The primary investment for the two-stage approach is in **dataset creation**, not compute. Budget for LLM API calls if generating synthetic data (e.g., GPT-4 for Q&A pair generation and quality filtering).

### 2.4 Recommended Hyperparameters

| Parameter | Suggested Value |
|---|---|
| Learning rate | 2e-4 (QLoRA) / 2e-5 (full fine-tune) |
| LoRA rank (r) | 16–64 |
| LoRA alpha | 32–64 |
| LoRA target modules | All linear layers (for best results) |
| Batch size | 4–8 (with gradient accumulation) |
| Epochs | 2–4 (monitor validation loss for convergence) |
| Max sequence length | 2048 (start here, increase if needed) |
| Optimizer | AdamW (8-bit via bitsandbytes for memory savings) |
| Scheduler | Cosine with warmup |

### 2.5 Example: Unsloth QLoRA Fine-Tuning Script

```python
from unsloth import FastLanguageModel
import torch

# Load base model in 4-bit
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/Qwen3-0.6B",  # or "Qwen/Qwen3-0.6B"
    max_seq_length=2048,
    load_in_4bit=True,
    dtype=None,  # auto-detect
)

# Apply LoRA adapters
model = FastLanguageModel.get_peft_model(
    model,
    r=32,
    lora_alpha=64,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                     "gate_proj", "up_proj", "down_proj"],
    lora_dropout=0,
    bias="none",
    use_gradient_checkpointing="unsloth",
)

# Configure trainer
from trl import SFTTrainer
from transformers import TrainingArguments

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=your_dataset,  # HuggingFace Dataset object
    args=TrainingArguments(
        output_dir="./outputs",
        per_device_train_batch_size=4,
        gradient_accumulation_steps=4,
        warmup_steps=10,
        num_train_epochs=3,
        learning_rate=2e-4,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        logging_steps=10,
        optim="adamw_8bit",
        save_strategy="epoch",
    ),
)

trainer.train()

# Save LoRA adapter
model.save_pretrained("./qwen3-0.6b-finetuned-lora")
tokenizer.save_pretrained("./qwen3-0.6b-finetuned-lora")
```

---

## 3. Post-Training: Merge & Convert

### 3.1 Merge LoRA Adapter into Base Model

After fine-tuning, the LoRA adapter is a small (~10–100 MB) file. It must be merged back into the base model to produce a standalone HuggingFace checkpoint before Cactus conversion.

**Using Unsloth:**

```python
# Merge and save as full HuggingFace model
model.save_pretrained_merged(
    "./qwen3-0.6b-finetuned-merged",
    tokenizer,
    save_method="merged_16bit",  # Full precision merged weights
)
```

**Using HuggingFace PEFT:**

```python
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

base_model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen3-0.6B")
model = PeftModel.from_pretrained(base_model, "./qwen3-0.6b-finetuned-lora")
merged_model = model.merge_and_unload()

merged_model.save_pretrained("./qwen3-0.6b-finetuned-merged")
tokenizer = AutoTokenizer.from_pretrained("Qwen/Qwen3-0.6B")
tokenizer.save_pretrained("./qwen3-0.6b-finetuned-merged")
```

**Compute requirements:** CPU-only, ~4 GB RAM, completes in minutes.

### 3.2 Convert to Cactus `.cact` Format

Using the Cactus conversion tool from the [cactus-compute/cactus](https://github.com/cactus-compute/cactus) repository:

```bash
# Clone the Cactus repo
git clone https://github.com/cactus-compute/cactus.git
cd cactus
source ./setup

# Install conversion dependencies
pip install -r tools/requirements.txt

# Convert your fine-tuned model
python3 tools/convert_hf.py \
    ./qwen3-0.6b-finetuned-merged \
    weights/qwen3-0.6b-finetuned/ \
    --precision INT8
```

Supported precision options: `INT4`, `INT8`, `FP16`. INT8 is the default used by Cactus for their official Qwen3-0.6B conversion. INT4 will produce a smaller model at the cost of some quality; FP16 preserves full precision but uses more RAM on-device.

**Compute requirements:** CPU-only, no GPU needed. For a 0.6B model, conversion completes in minutes on any modern machine.

---

## 4. Deployment to Flutter App on Pixel 7

There are two viable delivery paths for getting the converted model to the device.

### Option A: Bundle with Flutter App

Include the converted weight folder directly in your Flutter project's assets. The model will ship with the app binary.

```
your_flutter_project/
├── assets/
│   └── models/
│       └── qwen3-0.6b-finetuned/    # Cactus .cact weight folder
├── lib/
│   └── main.dart
└── pubspec.yaml
```

In `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/qwen3-0.6b-finetuned/
```

**Pros:** Works offline immediately after install. No download step needed. Simpler user experience.

**Cons:** Increases app bundle size significantly (~300–600 MB depending on quantization). May exceed Google Play Store size limits (150 MB AAB limit without Play Asset Delivery). Requires a new app release for every model update.

**Mitigation:** Use [Play Asset Delivery](https://developer.android.com/guide/playcore/asset-delivery) to deliver the model as an on-demand or install-time asset pack (up to 2 GB per pack).

### Option B: Download from Private HuggingFace Repository

Host the converted model on a private HuggingFace repo and download it at runtime.

**Step 1: Create a private HuggingFace repo and upload weights**

```bash
# Install HuggingFace CLI
pip install huggingface_hub

# Login
huggingface-cli login

# Create repo and upload
huggingface-cli repo create your-org/qwen3-0.6b-finetuned --private
huggingface-cli upload your-org/qwen3-0.6b-finetuned weights/qwen3-0.6b-finetuned/
```

**Step 2: Generate a read-only access token**

Go to [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) and create a fine-grained token with read-only access scoped to your specific repo.

**Step 3: Download in Flutter app**

```dart
import 'package:cactus/cactus.dart';

// Cactus SDK handles model downloads natively
final lm = await CactusLM.init(
  modelUrl: 'https://huggingface.co/your-org/qwen3-0.6b-finetuned/resolve/main/model-file',
  contextSize: 2048,
);
```

Alternatively, implement a custom download manager that fetches from the HF API with your token in the `Authorization` header:

```dart
import 'package:http/http.dart' as http;

Future<void> downloadModel(String repoId, String filename, String savePath) async {
  final url = 'https://huggingface.co/$repoId/resolve/main/$filename';
  final response = await http.get(
    Uri.parse(url),
    headers: {'Authorization': 'Bearer YOUR_HF_READ_TOKEN'},
  );

  if (response.statusCode == 200) {
    final file = File(savePath);
    await file.writeAsBytes(response.bodyBytes);
  }
}
```

**Pros:** App stays small. Can update model without a new app release. Version management via HuggingFace branches/tags.

**Cons:** Requires internet for first download. Needs local caching logic. Must securely manage the HF access token (do not hardcode — use environment config or a backend proxy).

### Option B Recommended Architecture

```
┌──────────────────┐     ┌────────────────────────┐     ┌──────────────────┐
│   Fine-Tuning    │     │  Private HuggingFace   │     │    Pixel 7       │
│   Environment    │────▶│  Repository            │────▶│    Flutter App   │
│   (Cloud GPU)    │     │  (Model Hosting)       │     │    + Cactus SDK  │
└──────────────────┘     └────────────────────────┘     └──────────────────┘
        │                         │                              │
   1. Fine-tune              2. Upload                   3. Download on
   2. Merge LoRA                .cact weights               first launch
   3. Convert to .cact                                   4. Cache locally
                                                         5. Run inference
```

### Security Considerations for Private Repo

- Never embed HuggingFace tokens directly in client code or Flutter assets.
- Use a lightweight backend endpoint that proxies download requests and injects the token server-side.
- Alternatively, generate short-lived presigned download URLs from your backend.
- Consider model integrity: verify downloaded weights via checksum before loading.

---

## 5. Complete Pipeline Summary

| Step | Action | Compute | Time | Cost |
|---|---|---|---|---|
| 1 | Prepare dataset (Q&A pairs) | CPU | Hours–days (manual effort) | LLM API costs for synthetic data |
| 2 | Fine-tune Qwen3-0.6B (QLoRA) | 1× GPU, 4–8 GB VRAM | 30 min – 2 hrs | < $1–2 (cloud) or free (Colab) |
| 3 | Merge LoRA adapter | CPU, ~4 GB RAM | ~2 min | Negligible |
| 4 | Convert to Cactus `.cact` format | CPU | ~2–5 min | Negligible |
| 5 | Upload to private HuggingFace repo | Internet | ~5 min | Free (HF free tier supports private repos) |
| 6 | Download in Flutter app + run inference | Pixel 7 on-device | Download: depends on connection. Inference: real-time | None |

**Total compute cost for the training pipeline: < $5 per iteration** (or free on Google Colab / Kaggle).

---

## 6. Iteration & Benchmarking Workflow

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Prepare /   │     │  Fine-Tune  │     │   Convert    │     │   Evaluate  │
│  Update      │────▶│  (QLoRA)    │────▶│   to .cact   │────▶│   Against   │
│  Dataset     │     │             │     │              │     │  Benchmark  │
└─────────────┘     └─────────────┘     └──────────────┘     └──────┬──────┘
       ▲                                                           │
       │                                                           │
       └──────── Adjust data / hyperparams based on results ◀──────┘
```

For each iteration:

1. Modify your training dataset or hyperparameters based on benchmark results.
2. Re-run fine-tuning (30 min – 2 hrs).
3. Merge and convert (~5 min).
4. Push to HuggingFace (or sideload for local testing).
5. Evaluate on your custom benchmark.
6. Repeat until performance targets are met.

---

## 7. References & Sources

- **Qwen3 Model Family:** [Qwen3 Blog](https://qwenlm.github.io/blog/qwen3/) — Architecture details, training methodology, benchmark results.
- **Cactus Compute Documentation:** [cactuscompute.com/docs/v1.7](https://cactuscompute.com/docs/v1.7) — Engine architecture, `.cact` format, performance benchmarks, supported models.
- **Cactus GitHub Repository:** [github.com/cactus-compute/cactus](https://github.com/cactus-compute/cactus) — Source code, `convert_hf.py` conversion tool, SDK documentation.
- **Unsloth Fine-Tuning Docs:** [unsloth.ai/docs](https://unsloth.ai/docs) — Qwen3 fine-tuning notebooks, VRAM requirements, QLoRA setup.
- **CROP Paper (NeurIPS 2024):** Zhang et al., "Empowering and Assessing the Utility of Large Language Models in Crop Science" — Two-stage instruction tuning methodology, dataset generation pipeline, fine-tuning results on 7B/8B models.
- **QLoRA Paper (NeurIPS 2023):** Dettmers et al., "QLoRA: Efficient Finetuning of Quantized LLMs" — 4-bit fine-tuning methodology demonstrating near full fine-tuning quality.
- **LLaMA Factory:** [github.com/hiyouga/LlamaFactory](https://github.com/hiyouga/LlamaFactory) — Multi-method fine-tuning framework with Qwen3 support.
- **GPU Requirements for Fine-Tuning:** [Runpod Blog](https://www.runpod.io/blog/llm-fine-tuning-gpu-guide), [DigitalOcean Guide](https://www.digitalocean.com/resources/articles/gpu-options-finetuning), [Gradient Flow Qwen3 Overview](https://gradientflow.com/qwen-3/) — Compute planning references.