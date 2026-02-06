#!/usr/bin/env python3
"""Query CactusLM Supabase API for available models."""

import json
import urllib.request

# CactusLM Supabase configuration (from cactus package source)
SUPABASE_URL = "https://vlqqczxwyaodtcdmdmlw.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZscXFjenh3eWFvZHRjZG1kbWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE1MTg2MzIsImV4cCI6MjA2NzA5NDYzMn0.nBzqGuK9j6RZ6mOPWU2boAC_5H9XDs-fPpo5P3WZYbI"


def fetch_models() -> list[dict]:
    """Fetch available models from CactusLM API."""
    url = f"{SUPABASE_URL}/functions/v1/get-models?sdk_name=flutter&sdk_version=1.3.0"

    request = urllib.request.Request(url)
    request.add_header("apikey", SUPABASE_KEY)
    request.add_header("Authorization", f"Bearer {SUPABASE_KEY}")

    with urllib.request.urlopen(request) as response:
        data = json.loads(response.read().decode())
        return data if isinstance(data, list) else [data]


def main() -> None:
    print("Fetching available models from CactusLM API...\n")

    try:
        models = fetch_models()

        print(f"Available models ({len(models)} total):")
        print("=" * 70)

        for model in models:
            slug = model.get("slug", "N/A")
            name = model.get("name", "N/A")
            quant = model.get("quantization", "N/A")
            download_url = model.get("download_url", "")

            print(f"Slug: {slug}")
            print(f"  Name: {name}")
            print(f"  Quantization: {quant}")
            if download_url:
                print(f"  URL: {download_url[:80]}...")
            print("-" * 50)

        # Find embedding models
        print("\n\nEmbedding models:")
        print("=" * 70)

        embedding_models = [
            m for m in models
            if "embed" in m.get("slug", "").lower() or "embed" in m.get("name", "").lower()
        ]

        if embedding_models:
            for model in embedding_models:
                print(f"Slug: {model.get('slug')}")
                print(f"  Name: {model.get('name')}")
        else:
            print("No embedding models found by name filter.")
            print("\nAll model slugs:")
            for model in models:
                print(f"  - {model.get('slug')}")

    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
