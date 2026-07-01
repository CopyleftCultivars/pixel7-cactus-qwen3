#!/usr/bin/env python3
"""
prepare_dataset.py - Convert source data to JSONL instruction-response pairs
for fine-tuning Qwen3-0.6B on natural farming / regenerative agriculture.

Supported input formats (auto-detected):
  1. MCQ JSONL  — natural_fertilizer_benchmark_v1.jsonl
                  Fields: question, A, B, C, D, answer, question_id, topic, source_document
  2. Recipe JSON — NF_Recipes.json
                  Fields: Recipe, Ingredients, Steps, Uses
  3. Generic JSONL — already in {"instruction": ..., "output": ...} format

Output schema:
  {"instruction": "...", "output": "..."}

Usage:
  python finetune/prepare_dataset.py \\
    --input /path/to/natural_fertilizer_benchmark_v1.jsonl \\
    --input /path/to/NF_Recipes.json \\
    --output-dir finetune/data/ \\
    --split 0.9 \\
    --seed 42

Generating synthetic Q&A from raw text (requires LLM API):
  Use the benchmark workspace's cleaned_text/ files as source corpus.
  Feed each passage to an LLM with the prompt:
    "Generate 5 instruction-response pairs about natural farming from this text.
     Return JSONL with fields 'instruction' and 'output'."
  Then pass the resulting JSONL as --input to this script.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path
from typing import Generator


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------

_OPTION_LETTERS = ("A", "B", "C", "D")


def _cyclic_shift(rec: dict, shift: int) -> tuple[dict[str, str], str]:
    """Return option texts and new gold letter after cyclically shifting by shift positions.

    shift=0 → original order; shift=1 → [D,A,B,C]; shift=2 → [C,D,A,B], etc.
    Balances gold-letter distribution across shifts to reduce positional bias.
    """
    orig = [rec[l] for l in _OPTION_LETTERS]
    shifted = orig[-shift:] + orig[:-shift] if shift > 0 else orig[:]
    options = {l: shifted[i] for i, l in enumerate(_OPTION_LETTERS)}
    gold_text = rec[rec["answer"].strip().upper()]
    new_gold = _OPTION_LETTERS[shifted.index(gold_text)]
    return options, new_gold


def _load_mcq_jsonl(path: Path) -> Generator[dict[str, str], None, None]:
    """Convert MCQ benchmark JSONL to instruction-response pairs.

    Each question produces:
      1. Open-ended variant: instruction = question, output = answer text only
      2. MCQ variants (×4 cyclic shifts): instruction = question + labelled options in
         each rotation, output = think-block + answer letter only.

    The 4 cyclic shifts balance the gold-letter distribution (A/B/C/D each appear
    equally as the correct position), fixing positional/D-avoidance bias in the model.
    The think-block output format teaches the model to reason then emit just the letter,
    matching what extract_answer expects during evaluation.
    """
    with open(path, encoding="utf-8") as fh:
        for raw_line in fh:
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                rec = json.loads(raw_line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSON in {path}: {exc}") from exc

            required = {"question", "A", "B", "C", "D", "answer"}
            missing = required - rec.keys()
            if missing:
                raise ValueError(f"Record missing fields {missing}: {raw_line[:80]}")

            letter = rec["answer"].strip().upper()
            if letter not in _OPTION_LETTERS:
                raise ValueError(f"Unexpected answer letter '{letter}' in {raw_line[:80]}")

            answer_text: str = rec[letter].strip()
            question: str = rec["question"].strip()

            # Variant 1 — open-ended (no options, plain answer text)
            yield {
                "instruction": question,
                "output": answer_text,
            }

            # Variant 2 — MCQ with labelled options, 4 cyclic shifts for bias balance.
            # Output uses think-block format so the model learns to:
            #   (a) produce <think>...</think> then emit just the answer letter, and
            #   (b) answer correctly regardless of which position the correct option occupies.
            for shift in range(4):
                opts, new_letter = _cyclic_shift(rec, shift)
                new_answer_text = opts[new_letter]
                options_block = "\n".join(f"{l}. {opts[l]}" for l in _OPTION_LETTERS)
                yield {
                    "instruction": f"{question}\n\n{options_block}",
                    "output": (
                        f"<think>\nThe correct answer is {new_letter}. {new_answer_text}\n</think>\n{new_letter}"
                    ),
                }


def _load_recipe_json(path: Path) -> Generator[dict[str, str], None, None]:
    """Convert NF_Recipes.json to instruction-response pairs.

    Each recipe produces up to three pairs:
      1. How to make it (steps)
      2. What ingredients are needed
      3. What it is used for
    """
    with open(path, encoding="utf-8") as fh:
        try:
            records = json.load(fh)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON in {path}: {exc}") from exc

    if not isinstance(records, list):
        raise ValueError(f"{path} must contain a JSON array of recipe objects")

    for rec in records:
        name: str = rec.get("Recipe", "").strip()
        if not name:
            continue

        steps: list[str] = rec.get("Steps", [])
        ingredients: list[str] = rec.get("Ingredients", [])
        uses: list[str] = rec.get("Uses", [])

        if steps:
            steps_text = "\n".join(f"{i + 1}. {s}" for i, s in enumerate(steps))
            yield {
                "instruction": f"How do I make {name}?",
                "output": steps_text,
            }

        if ingredients:
            ing_text = "\n".join(f"- {ing}" for ing in ingredients)
            yield {
                "instruction": f"What ingredients do I need to prepare {name}?",
                "output": ing_text,
            }

        if uses:
            uses_text = "\n".join(f"- {u}" for u in uses)
            yield {
                "instruction": f"What are the uses and benefits of {name}?",
                "output": uses_text,
            }


def _load_generic_jsonl(path: Path) -> Generator[dict[str, str], None, None]:
    """Load a JSONL file already in {instruction, output} format."""
    with open(path, encoding="utf-8") as fh:
        for lineno, raw_line in enumerate(fh, start=1):
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                rec = json.loads(raw_line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{lineno}: Invalid JSON: {exc}") from exc

            if "instruction" not in rec or "output" not in rec:
                raise ValueError(
                    f"{path}:{lineno}: Record must have 'instruction' and 'output' fields"
                )
            yield {"instruction": str(rec["instruction"]), "output": str(rec["output"])}


def _detect_and_load(path: Path) -> Generator[dict[str, str], None, None]:
    """Auto-detect file format and dispatch to the correct loader."""
    suffix = path.suffix.lower()
    if suffix == ".json":
        # Could be recipe JSON or a JSON array of instruction pairs
        with open(path, encoding="utf-8") as fh:
            probe = json.load(fh)
        if isinstance(probe, list) and probe and "Recipe" in probe[0]:
            yield from _load_recipe_json(path)
        elif isinstance(probe, list) and probe and "instruction" in probe[0]:
            # JSON array of instruction pairs — write temp JSONL and re-load
            for rec in probe:
                yield {"instruction": str(rec["instruction"]), "output": str(rec["output"])}
        else:
            raise ValueError(
                f"Cannot determine format of {path}. "
                "Expected NF_Recipes.json style or [{instruction, output}] array."
            )
    elif suffix == ".jsonl":
        # Peek at the first line to distinguish MCQ from generic instruction format
        with open(path, encoding="utf-8") as fh:
            first = fh.readline().strip()
        if not first:
            return
        probe = json.loads(first)
        if {"question", "A", "B", "C", "D", "answer"}.issubset(probe.keys()):
            yield from _load_mcq_jsonl(path)
        elif "instruction" in probe and "output" in probe:
            yield from _load_generic_jsonl(path)
        else:
            raise ValueError(
                f"Cannot determine JSONL schema for {path}. "
                "Expected MCQ fields or {{instruction, output}}."
            )
    else:
        raise ValueError(f"Unsupported file extension '{suffix}' for {path}. Use .json or .jsonl")


# ---------------------------------------------------------------------------
# Filtering & deduplication
# ---------------------------------------------------------------------------

def _char_count(pair: dict[str, str]) -> int:
    return len(pair["instruction"]) + len(pair["output"])


def _instruction_hash(pair: dict[str, str]) -> str:
    return hashlib.sha256(pair["instruction"].encode()).hexdigest()


def filter_and_dedup(
    pairs: list[dict[str, str]],
    min_output_chars: int,
    max_total_chars: int,
) -> list[dict[str, str]]:
    seen: set[str] = set()
    result: list[dict[str, str]] = []
    skipped_short = skipped_long = skipped_dup = 0

    for pair in pairs:
        output_len = len(pair["output"].strip())
        if output_len < min_output_chars:
            skipped_short += 1
            continue
        total = _char_count(pair)
        if total > max_total_chars:
            skipped_long += 1
            continue
        h = _instruction_hash(pair)
        if h in seen:
            skipped_dup += 1
            continue
        seen.add(h)
        result.append(pair)

    print(
        f"  Filtered: {skipped_short} too short, "
        f"{skipped_long} too long, "
        f"{skipped_dup} duplicate instructions",
        file=sys.stderr,
    )
    return result


# ---------------------------------------------------------------------------
# Split & write
# ---------------------------------------------------------------------------

def split_and_write(
    pairs: list[dict[str, str]],
    output_dir: Path,
    train_fraction: float,
    seed: int,
) -> tuple[int, int]:
    random.seed(seed)
    shuffled = pairs.copy()
    random.shuffle(shuffled)

    split_idx = max(1, int(len(shuffled) * train_fraction))
    train = shuffled[:split_idx]
    val = shuffled[split_idx:]

    output_dir.mkdir(parents=True, exist_ok=True)
    train_path = output_dir / "train.jsonl"
    val_path = output_dir / "val.jsonl"

    for dest, records in ((train_path, train), (val_path, val)):
        with open(dest, "w", encoding="utf-8") as fh:
            for rec in records:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")

    return len(train), len(val)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert source data to JSONL instruction-response pairs for fine-tuning.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--input",
        dest="inputs",
        action="append",
        required=True,
        metavar="PATH",
        help="Input file (.json or .jsonl). Repeat to combine multiple sources.",
    )
    parser.add_argument(
        "--output-dir",
        default="finetune/data",
        metavar="DIR",
        help="Directory for train.jsonl and val.jsonl (default: finetune/data)",
    )
    parser.add_argument(
        "--split",
        type=float,
        default=0.9,
        metavar="FRACTION",
        help="Fraction of data for training (default: 0.9)",
    )
    parser.add_argument(
        "--min-output-chars",
        type=int,
        default=20,
        metavar="N",
        help="Minimum characters in output field (default: 20)",
    )
    parser.add_argument(
        "--max-total-chars",
        type=int,
        default=4096,
        metavar="N",
        help="Maximum combined instruction+output characters (default: 4096)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducible splits (default: 42)",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not 0.0 < args.split < 1.0:
        parser.error("--split must be between 0 and 1 (exclusive)")

    all_pairs: list[dict[str, str]] = []

    for raw_path in args.inputs:
        path = Path(raw_path)
        if not path.exists():
            parser.error(f"Input path does not exist: {path}")
        print(f"Loading {path} ...", file=sys.stderr)
        try:
            pairs = list(_detect_and_load(path))
        except (ValueError, json.JSONDecodeError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            sys.exit(1)
        print(f"  Loaded {len(pairs)} pairs from {path.name}", file=sys.stderr)
        all_pairs.extend(pairs)

    print(f"\nTotal before filtering: {len(all_pairs)}", file=sys.stderr)
    filtered = filter_and_dedup(
        all_pairs,
        min_output_chars=args.min_output_chars,
        max_total_chars=args.max_total_chars,
    )
    print(f"Total after filtering:  {len(filtered)}", file=sys.stderr)

    if not filtered:
        print(
            "ERROR: No pairs remain after filtering. "
            "Adjust --min-output-chars or --max-total-chars.",
            file=sys.stderr,
        )
        sys.exit(1)

    output_dir = Path(args.output_dir)
    n_train, n_val = split_and_write(filtered, output_dir, args.split, args.seed)

    print(f"\nWrote {n_train} train pairs → {output_dir}/train.jsonl", file=sys.stderr)
    print(f"Wrote {n_val}  val pairs   → {output_dir}/val.jsonl", file=sys.stderr)


if __name__ == "__main__":
    main()
