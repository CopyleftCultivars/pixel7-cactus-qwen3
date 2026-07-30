#!/usr/bin/env python3
"""Strip vision tower weights from a Gemma4ForConditionalGeneration safetensors model.

Produces a text-only version of the model for on-device deployment where the
vision encoder is not needed. The output is a new directory with a filtered
model.safetensors and an updated config.json with vision_config removed.

Usage:
    python3 conversion/strip_vision_encoder.py \
        --input  /path/to/gemma4-merged \
        --output /path/to/gemma4-text-only
"""

import argparse
import json
import shutil
from pathlib import Path

import torch
from safetensors import safe_open
from safetensors.torch import save_file


VISION_PREFIXES = (
    "model.vision_tower.",
    "model.multi_modal_projector.",
    "model.embed_vision.",
    "model.audio_tower.",
    "model.embed_audio.",
)

VISION_CONFIG_KEYS = ("vision_config", "audio_config")

TOKENIZER_FILES = [
    "tokenizer.json",
    "tokenizer_config.json",
    "tokenizer.model",
    "special_tokens_map.json",
    "added_tokens.json",
    "chat_template.jinja",
    "generation_config.json",
]


def strip_vision(input_dir: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading safetensors from {input_dir} ...")
    state_dict: dict[str, torch.Tensor] = {}
    for f in sorted(input_dir.glob("*.safetensors")):
        with safe_open(str(f), framework="pt", device="cpu") as sf:
            for key in sf.keys():
                state_dict[key] = sf.get_tensor(key)

    total = len(state_dict)
    kept = {k: v for k, v in state_dict.items()
            if not any(k.startswith(p) for p in VISION_PREFIXES)}
    dropped = total - len(kept)

    dropped_bytes = sum(
        v.numel() * v.element_size()
        for k, v in state_dict.items()
        if any(k.startswith(p) for p in VISION_PREFIXES)
    )
    kept_bytes = sum(v.numel() * v.element_size() for v in kept.values())

    print(f"Dropped {dropped} vision tensors ({dropped_bytes / 1e9:.2f} GB)")
    print(f"Keeping {len(kept)} language tensors ({kept_bytes / 1e9:.2f} GB)")

    out_safetensors = output_dir / "model.safetensors"
    print(f"Saving stripped model to {out_safetensors} ...")
    save_file(kept, str(out_safetensors))

    config_path = input_dir / "config.json"
    if config_path.exists():
        config = json.loads(config_path.read_text(encoding="utf-8"))
        for key in VISION_CONFIG_KEYS:
            config.pop(key, None)
        (output_dir / "config.json").write_text(
            json.dumps(config, indent=2), encoding="utf-8"
        )
        print("Wrote stripped config.json (removed vision_config and audio_config)")

    for name in TOKENIZER_FILES:
        src = input_dir / name
        if src.exists():
            shutil.copy2(src, output_dir / name)
            print(f"Copied {name}")

    print(f"\nDone. Text-only model written to: {output_dir}")
    print(f"Estimated 4-bit size: ~{kept_bytes / 1e9 / 4:.2f} GB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path,
                        help="Path to merged Gemma4 model directory")
    parser.add_argument("--output", required=True, type=Path,
                        help="Output directory for text-only model")
    args = parser.parse_args()

    if not args.input.is_dir():
        raise FileNotFoundError(f"Input directory not found: {args.input}")
    if not list(args.input.glob("*.safetensors")):
        raise FileNotFoundError(f"No .safetensors files found in {args.input}")

    strip_vision(args.input, args.output)


if __name__ == "__main__":
    main()
