#!/usr/bin/env python3
"""
Host-Side Embedding Generator for CactusRAG

This script generates embeddings for the knowledge base on the host machine,
which can then be pushed to the Android device to speed up first launch.

Usage:
    conda activate clc_local
    pip install llama-cpp-python huggingface-hub
    python generate_embeddings.py

Output:
    - embeddings_precomputed.json: Embeddings for all knowledge base chunks
    - Can be pushed to device and loaded by Flutter app
"""

import json
import hashlib
import sys
from pathlib import Path
from typing import Generator

# Configuration matching Flutter RAG service
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 200

# Model configuration
MODEL_REPO = "Qwen/Qwen3-Embedding-0.6B-GGUF"
MODEL_FILE = "qwen3-embedding-0.6b-q8_0.gguf"
MODEL_DIR = Path("models")

# Knowledge base path
KNOWLEDGE_BASE_PATH = Path("natural_farming_chat/assets/knowledge/nutrients_knowledge.md")

# Output paths
OUTPUT_DIR = Path("precomputed_embeddings")
OUTPUT_FILE = OUTPUT_DIR / "embeddings_precomputed.json"


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


def chunk_text(
    text: str,
    chunk_size: int = CHUNK_SIZE,
    chunk_overlap: int = CHUNK_OVERLAP,
) -> Generator[tuple[int, str], None, None]:
    """
    Split text into overlapping chunks.

    Matches CactusRAG chunking behavior.

    Yields:
        Tuple of (chunk_index, chunk_text)
    """
    if len(text) <= chunk_size:
        yield (0, text)
        return

    start = 0
    chunk_index = 0

    while start < len(text):
        end = start + chunk_size

        # Don't create tiny final chunks
        if end >= len(text):
            yield (chunk_index, text[start:])
            break

        # Find a good break point (newline, period, space)
        break_point = end
        for sep in ["\n\n", "\n", ". ", " "]:
            pos = text.rfind(sep, start, end)
            if pos > start + chunk_size // 2:
                break_point = pos + len(sep)
                break

        chunk = text[start:break_point].strip()
        if chunk:
            yield (chunk_index, chunk)
            chunk_index += 1

        # Move forward with overlap
        start = break_point - chunk_overlap
        if start < 0:
            start = 0


def compute_content_hash(content: str) -> str:
    """Compute SHA256 hash of content for cache invalidation."""
    return hashlib.sha256(content.encode("utf-8")).hexdigest()[:16]


def load_llama_model(model_path: Path):
    """Load llama-cpp-python model for embedding generation."""
    try:
        from llama_cpp import Llama, LLAMA_POOLING_TYPE_LAST
    except ImportError:
        print("Error: llama-cpp-python not installed.")
        print("Run: pip install llama-cpp-python")
        sys.exit(1)

    print("Loading model...")
    llm = Llama(
        model_path=str(model_path),
        embedding=True,
        pooling_type=LLAMA_POOLING_TYPE_LAST,
        n_ctx=512,
        verbose=False,
    )
    return llm


def generate_embedding(llm, text: str) -> list[float]:
    """Generate embedding for a single text using llama-cpp-python."""
    response = llm.create_embedding(text)
    return response["data"][0]["embedding"]


def main():
    print("=" * 60)
    print("Host-Side Embedding Generator")
    print("=" * 60)
    print()

    # Check knowledge base exists
    if not KNOWLEDGE_BASE_PATH.exists():
        print(f"Error: Knowledge base not found at {KNOWLEDGE_BASE_PATH}")
        sys.exit(1)

    # Read knowledge base
    print(f"Reading knowledge base from {KNOWLEDGE_BASE_PATH}...")
    with open(KNOWLEDGE_BASE_PATH, encoding="utf-8") as f:
        content = f.read()

    content_hash = compute_content_hash(content)
    print(f"Content hash: {content_hash}")
    print(f"Content size: {len(content):,} characters")
    print()

    # Chunk the content
    print(f"Chunking with size={CHUNK_SIZE}, overlap={CHUNK_OVERLAP}...")
    chunks = list(chunk_text(content))
    print(f"Generated {len(chunks)} chunks")
    print()

    # Download/load model
    model_path = download_model()
    llm = load_llama_model(model_path)
    print()

    # Generate embeddings for all chunks
    print("Generating embeddings...")
    embeddings_data = []

    for i, (chunk_index, chunk_content) in enumerate(chunks):
        progress = (i + 1) / len(chunks) * 100
        print(f"  [{i+1}/{len(chunks)}] ({progress:.1f}%) Chunk {chunk_index}...", end="")

        embedding = generate_embedding(llm, chunk_content)
        print(f" dim={len(embedding)}")

        embeddings_data.append({
            "chunk_index": chunk_index,
            "content": chunk_content,
            "content_hash": compute_content_hash(chunk_content),
            "embedding": embedding,
            "dimension": len(embedding),
        })

    print()

    # Create output structure
    output = {
        "version": 1,
        "generator": "llama-cpp-python",
        "model": f"{MODEL_REPO}/{MODEL_FILE}",
        "source_file": str(KNOWLEDGE_BASE_PATH),
        "source_hash": content_hash,
        "chunk_size": CHUNK_SIZE,
        "chunk_overlap": CHUNK_OVERLAP,
        "total_chunks": len(chunks),
        "embedding_dimension": embeddings_data[0]["dimension"] if embeddings_data else 0,
        "chunks": embeddings_data,
    }

    # Save output
    OUTPUT_DIR.mkdir(exist_ok=True)
    print(f"Saving to {OUTPUT_FILE}...")

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f)

    # Also save a compact version without content (just embeddings)
    compact_file = OUTPUT_DIR / "embeddings_compact.json"
    compact_output = {
        "version": output["version"],
        "source_hash": output["source_hash"],
        "chunk_size": output["chunk_size"],
        "chunk_overlap": output["chunk_overlap"],
        "embedding_dimension": output["embedding_dimension"],
        "embeddings": [
            {
                "chunk_index": chunk["chunk_index"],
                "content_hash": chunk["content_hash"],
                "embedding": chunk["embedding"],
            }
            for chunk in embeddings_data
        ],
    }

    with open(compact_file, "w", encoding="utf-8") as f:
        json.dump(compact_output, f)

    print(f"Saved compact version to {compact_file}")
    print()

    # Summary
    file_size = OUTPUT_FILE.stat().st_size
    compact_size = compact_file.stat().st_size
    print("=" * 60)
    print("Summary:")
    print(f"  Total chunks: {len(chunks)}")
    print(f"  Embedding dimension: {output['embedding_dimension']}")
    print(f"  Full output size: {file_size / 1024 / 1024:.2f} MB")
    print(f"  Compact output size: {compact_size / 1024 / 1024:.2f} MB")
    print()
    print("Next steps:")
    print("  1. Run test_embedding_compatibility.py to verify compatibility")
    print("  2. Push embeddings to device with ADB (issue #14)")
    print("  3. Modify Flutter app to load pre-computed embeddings (issue #20)")
    print("=" * 60)


if __name__ == "__main__":
    main()
