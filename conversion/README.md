# Cactus conversion tools

These scripts handle the model artifact boundary only. Training, fine-tuning, and dataset preparation are intentionally outside this repository.

## Convert a Hugging Face checkpoint

    bash conversion/convert_to_cactus.sh \
      --merged-model /path/to/huggingface-model \
      --output models/cactus-model \
      --bits 4 \
      --cache-context-length 2048

The input directory must contain at least one .safetensors file. The script clones or reuses the Cactus SDK, then requires its official CLI in conversion/cactus-sdk/venv/. It produces the CQ weights and runtime components needed by the Flutter package and verifies components/manifest.json.

## Optional vision stripping

For a Gemma4 or other multimodal checkpoint that will be used as a text-only model:

    python3 conversion/strip_vision_encoder.py \
      --input /path/to/merged-model \
      --output /path/to/text-only-model

Pass the resulting directory to convert_to_cactus.sh.

## Publish converted weights

    bash conversion/upload_to_hf.sh \
      --model-dir models/cactus-model \
      --repo YOUR_HF_USERNAME/your-model

The Cactus SDK checkout, model inputs, outputs, and archives are ignored by git; only the conversion scripts are committed.
