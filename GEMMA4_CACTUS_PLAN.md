# Plan: Convert Finetuned Gemma4-E2B-IT to Cactus Format and Deploy to Flutter App

## Context

The current pipeline fine-tunes Qwen3-0.6B on natural farming data, converts it to Cactus `.cact` format, and deploys via a Flutter app to Pixel 7. This benchmarks at ~70% on the Natural Fertilizer MCQ dataset. The goal is to swap in a finetuned Gemma4-E2B-IT model (already merged locally) using the same pipeline — potentially improving benchmark scores — and land it on a separate Flutter branch pointing to a new HuggingFace repo.

**Critical pre-condition**: The local cactus-sdk only explicitly supports Gemma-3. The Cactus team has reportedly posted Gemma4 support to HuggingFace. We must update the SDK before attempting conversion.

---

## Phase 0 (First): Tag the Working Qwen3 Baseline

Before any changes, mark the current known-working commit as a safe rollback point:

```bash
git tag qwen3-cactus
git push origin qwen3-cactus
```

Then create the Gemma4 branch from this same commit:

```bash
git checkout -b gemma4-cactus-model
```

All library changes, SDK updates, and `model_service.dart` edits for Gemma4 happen on `gemma4-cactus-model`. The branch only merges into master once the full plan is verified end-to-end (conversion → Pixel 7 runs → benchmark passes → HuggingFace upload works → Flutter downloads and runs). If anything gets stuck, `git checkout qwen3-cactus` restores the exact working state.

---

## Phase 1: Audit Cactus SDK for Gemma4 Support

**Goal**: Get a Cactus SDK that can convert Gemma4 architecture.

1. Check HuggingFace `cactus-compute` org for any Gemma4 model or updated SDK:
   - Look for a Gemma4 pre-converted model (would confirm format support)
   - Look for SDK updates or a `convert_hf.py` with Gemma4 arch handling

2. Update `finetune/cactus-sdk/` by pulling the latest from `cactus-compute/cactus` on GitHub:
   ```bash
   cd finetune/cactus-sdk && git pull origin main
   ```
   Then inspect `tools/convert_hf.py` and `python/src/config_utils.py` for Gemma4 arch detection.

3. If `detect_model_type()` in `config_utils.py` returns `'gemma'` for a Gemma4 model but weight patterns don't handle Gemma4's architecture, add arch-specific handling. Gemma4 uses `num_key_value_heads` distinct from `num_attention_heads` in some sizes.

**Deliverable**: Confirmed working `convert_hf.py` that handles Gemma4 architecture.

---

## Phase 2: Verify the Merged Gemma4 Model

**Goal**: Confirm the locally merged model is conversion-ready.

- Local merged model: `/home/goya/CopyLeftCultivars/finetune-gemma4/gemma4-merged/`
- Verify it contains: `config.json`, `tokenizer.json`, `tokenizer_config.json`, `*.safetensors`
- Check `config.json` → `model_type` to confirm the exact architecture string the SDK will see
- Confirm whether this is the e2b (2B) or e4b (4B) variant — determines INT4 vs INT8 feasibility

**Size risk**: At INT8, a 2B model ≈ 2GB; 4B ≈ 4GB. Pixel 7 has 8GB RAM with ~3–4GB available to apps. Use **INT4** precision for the initial attempt to keep the model under 1–2GB.

---

## Phase 3: Convert to Cactus Format

Adapt the existing `finetune/convert_to_cactus.sh` to point at the Gemma4 merged model:

```bash
bash finetune/convert_to_cactus.sh \
  --merged-model /home/goya/CopyLeftCultivars/finetune-gemma4/gemma4-merged \
  --output finetune/outputs/gemma4-cact-model \
  --precision INT4 \
  --cactus-dir finetune/cactus-sdk
```

- Start with **INT4** (smallest footprint for on-device testing)
- If INT4 produces degraded quality in benchmarks, retry with INT8
- Output `.cact` files land in `finetune/outputs/gemma4-cact-model/`

If `convert_hf.py` fails on Gemma4 arch, the fix is in `config_utils.py:detect_model_type()`.

---

## Phase 4: On-Device Testing on Pixel 7

**Goal**: Confirm the converted model runs and produces coherent output.

1. Sideload the `.cact` model to the Flutter app via ADB or the app's download mechanism
2. Verify basic inference — look for garbled output (wrong chat template) or OOM crashes
3. **Gemma4 chat template** differs from ChatML — update `model_service.dart` on the branch:
   - Qwen3/ChatML: `<|im_start|>user\n...<|im_end|>\n<|im_start|>assistant\n`
   - Gemma: `<start_of_turn>user\n...<end_of_turn>\n<start_of_turn>model\n`
4. Run the benchmark:
   ```bash
   adb forward tcp:11435 tcp:11435
   python benchmark/oc_eval/run_cactus_pixel.py
   ```
   Compare result to the Qwen3 baseline of ~70%.

---

## Phase 5: Upload to HuggingFace

**Goal**: Publish the Gemma4 Cactus model for the Flutter app to download.

```bash
bash finetune/upload_to_hf.sh \
  --model-dir finetune/outputs/gemma4-cact-model \
  --repo CopyLeftCultivars/gemma4-nf-finetuned-cactus \
  --filename gemma4-nf-finetuned.zip
```

Add a model card with: base model, fine-tuning dataset, Cactus INT4 format, and benchmark result vs Qwen3 baseline. Save the printed download URL for Phase 6.

---

## Phase 6: Update Flutter Branch

Edit `natural_farming_chat/lib/services/model_service.dart` on `gemma4-cactus-model` branch:
- `_modelDownloadUrl` → new HuggingFace zip URL from Phase 5
- `_modelSlug` → `'gemma4-nf-finetuned'`
- Chat template: update prompt wrapping from ChatML to Gemma format
- Verify `packages/cactus` local fork's `libcactus.so` supports Gemma4 inference

Test on Pixel 7 (cold start download → inference). Push branch. Merge into master only after full verification.

---

## Critical Files

| File | Role |
|---|---|
| `finetune/convert_to_cactus.sh` | Conversion orchestrator — reuse, change `--merged-model` path |
| `finetune/cactus-sdk/python/src/config_utils.py` | Gemma4 arch detection — may need edit |
| `finetune/cactus-sdk/tools/convert_hf.py` | Core conversion weight mapping |
| `finetune/upload_to_hf.sh` | HuggingFace upload — reuse as-is |
| `natural_farming_chat/lib/services/model_service.dart` | Model URL, slug, chat template |
| `/home/goya/CopyLeftCultivars/finetune-gemma4/gemma4-merged/` | Source model for conversion |
| `benchmark/oc_eval/run_cactus_pixel.py` | Benchmark runner — reuse as-is |

---

## Verification Checklist

- [ ] `finetune/outputs/gemma4-cact-model/` contains `.cact` files
- [ ] App responds coherently to a farming question on Pixel 7
- [ ] `run_cactus_pixel.py` result JSON produced; compare to 70% Qwen3 baseline
- [ ] HuggingFace download link resolves and zip extracts
- [ ] Flutter `gemma4-cactus-model` branch cold-start downloads and runs Gemma4 model
- [ ] Merge into master only after all boxes checked
