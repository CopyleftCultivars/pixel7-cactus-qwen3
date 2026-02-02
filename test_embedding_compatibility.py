#!/usr/bin/env python3
"""
Embedding Compatibility Test Script

Tests if llama-cpp-python generates embeddings compatible with Cactus/CactusRAG.
This script downloads the Qwen3-Embedding-0.6B GGUF model and generates embeddings
that can be compared with embeddings from the Flutter app.

Usage:
    pip install llama-cpp-python huggingface-hub
    python test_embedding_compatibility.py

The script will:
1. Download the Qwen3-Embedding-0.6B-GGUF model (if not present)
2. Generate embeddings for test phrases
3. Output embeddings in JSON format for comparison with Cactus

To compare with Cactus embeddings:
1. Run this script and save output
2. Add debug logging to the Flutter app (see issue #18)
3. Query the same test phrases in the Flutter app
4. Compare the embedding vectors
"""

import json
import sys
from pathlib import Path
from typing import Optional

# Model configuration
MODEL_REPO = "Qwen/Qwen3-Embedding-0.6B-GGUF"
MODEL_FILE = "qwen3-embedding-0.6b-q8_0.gguf"
MODEL_DIR = Path("models")

# Test phrases for embedding comparison
TEST_PHRASES = [
    "What is nitrogen fixation?",
    "How do I make compost tea?",
    "natural farming fertilizer",
    "potassium deficiency symptoms",
]


def download_model() -> Path:
    """Download the embedding model from HuggingFace if not present."""
    model_path = MODEL_DIR / MODEL_FILE

    if model_path.exists():
        print(f"Model already exists at {model_path}")
        return model_path

    print(f"Downloading {MODEL_REPO}/{MODEL_FILE}...")
    MODEL_DIR.mkdir(exist_ok=True)

    try:
        from huggingface_hub import hf_hub_download

        downloaded_path = hf_hub_download(
            repo_id=MODEL_REPO,
            filename=MODEL_FILE,
            local_dir=MODEL_DIR,
            local_dir_use_symlinks=False,
        )
        print(f"Downloaded to {downloaded_path}")
        return Path(downloaded_path)
    except ImportError:
        print("Error: huggingface-hub not installed.")
        print("Run: pip install huggingface-hub")
        sys.exit(1)


def generate_embeddings_llama_cpp(
    model_path: Path,
    texts: list[str],
    pooling_type: str = "last",
) -> list[dict]:
    """Generate embeddings using llama-cpp-python.

    Args:
        model_path: Path to the GGUF model file
        texts: List of texts to embed
        pooling_type: Pooling type (none, mean, cls, last, rank)

    Returns:
        List of dicts with 'text', 'embedding', 'dimension' keys
    """
    try:
        from llama_cpp import Llama, LLAMA_POOLING_TYPE_LAST, LLAMA_POOLING_TYPE_MEAN
    except ImportError:
        print("Error: llama-cpp-python not installed.")
        print("Run: pip install llama-cpp-python")
        sys.exit(1)

    # Map pooling type string to constant
    pooling_map = {
        "last": LLAMA_POOLING_TYPE_LAST,
        "mean": LLAMA_POOLING_TYPE_MEAN,
    }

    pooling_value = pooling_map.get(pooling_type)
    if pooling_value is None:
        print(f"Warning: Unknown pooling type '{pooling_type}', using 'last'")
        pooling_value = LLAMA_POOLING_TYPE_LAST

    print(f"Loading model with pooling_type={pooling_type}...")
    llm = Llama(
        model_path=str(model_path),
        embedding=True,
        pooling_type=pooling_value,
        n_ctx=512,  # Context size for embeddings
        verbose=False,
    )

    results = []
    for text in texts:
        print(f"  Embedding: '{text[:50]}...'")
        response = llm.create_embedding(text)

        # Extract embedding from response
        embedding = response["data"][0]["embedding"]

        results.append({
            "text": text,
            "embedding": embedding,
            "dimension": len(embedding),
        })

    return results


def compare_embeddings(
    embedding1: list[float],
    embedding2: list[float],
) -> dict:
    """Compare two embeddings and return similarity metrics."""
    import math

    if len(embedding1) != len(embedding2):
        return {
            "error": f"Dimension mismatch: {len(embedding1)} vs {len(embedding2)}",
            "match": False,
        }

    # Cosine similarity
    dot_product = sum(a * b for a, b in zip(embedding1, embedding2))
    norm1 = math.sqrt(sum(a * a for a in embedding1))
    norm2 = math.sqrt(sum(b * b for b in embedding2))
    cosine_sim = dot_product / (norm1 * norm2) if norm1 > 0 and norm2 > 0 else 0

    # Euclidean distance
    euclidean_dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(embedding1, embedding2)))

    # Check if embeddings are nearly identical (within tolerance)
    tolerance = 1e-5
    max_diff = max(abs(a - b) for a, b in zip(embedding1, embedding2))

    return {
        "cosine_similarity": cosine_sim,
        "euclidean_distance": euclidean_dist,
        "max_element_diff": max_diff,
        "match": max_diff < tolerance,
    }


def save_embeddings_for_comparison(results: list[dict], output_file: Path) -> None:
    """Save embeddings to JSON file for comparison with Cactus output."""
    output = {
        "generator": "llama-cpp-python",
        "model": f"{MODEL_REPO}/{MODEL_FILE}",
        "embeddings": results,
    }

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)

    print(f"Saved embeddings to {output_file}")


def load_cactus_embeddings(input_file: Path) -> Optional[list[dict]]:
    """Load Cactus embeddings from JSON file for comparison."""
    if not input_file.exists():
        return None

    with open(input_file) as f:
        data = json.load(f)

    return data.get("embeddings", [])


def main():
    print("=" * 60)
    print("Embedding Compatibility Test")
    print("=" * 60)
    print()

    # Download model
    model_path = download_model()
    print()

    # Generate embeddings with llama-cpp-python
    print("Generating embeddings with llama-cpp-python...")
    results = generate_embeddings_llama_cpp(
        model_path,
        TEST_PHRASES,
        pooling_type="last",  # Qwen3-Embedding uses 'last' pooling
    )
    print()

    # Display results
    print("Embedding Results:")
    print("-" * 40)
    for result in results:
        print(f"Text: {result['text']}")
        print(f"Dimension: {result['dimension']}")
        print(f"First 5 values: {result['embedding'][:5]}")
        print(f"Last 5 values: {result['embedding'][-5:]}")
        print()

    # Save for comparison
    output_file = Path("embeddings_llama_cpp.json")
    save_embeddings_for_comparison(results, output_file)
    print()

    # Check if Cactus embeddings exist for comparison
    cactus_file = Path("embeddings_cactus.json")
    cactus_results = load_cactus_embeddings(cactus_file)

    if cactus_results:
        print("Comparing with Cactus embeddings...")
        print("-" * 40)

        for llama_result in results:
            cactus_match = next(
                (c for c in cactus_results if c["text"] == llama_result["text"]),
                None,
            )

            if cactus_match:
                comparison = compare_embeddings(
                    llama_result["embedding"],
                    cactus_match["embedding"],
                )
                print(f"Text: {llama_result['text']}")
                print(f"  Cosine similarity: {comparison.get('cosine_similarity', 'N/A'):.6f}")
                print(f"  Euclidean distance: {comparison.get('euclidean_distance', 'N/A'):.6f}")
                print(f"  Max element diff: {comparison.get('max_element_diff', 'N/A'):.6f}")
                print(f"  Match: {comparison.get('match', False)}")
                print()
    else:
        print(f"No Cactus embeddings found at {cactus_file}")
        print("To generate Cactus embeddings for comparison:")
        print("1. Add debug logging to the Flutter app (issue #18)")
        print("2. Run the app and query the same test phrases")
        print("3. Export embeddings to embeddings_cactus.json")
        print()

    print("=" * 60)
    print("Done!")


if __name__ == "__main__":
    main()
