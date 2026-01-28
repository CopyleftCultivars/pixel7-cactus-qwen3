import os
import sys
from pathlib import Path

# Check and install missing dependencies
def check_dependencies():
    """Check if required packages are installed."""
    required_packages = {
        'yaml': 'PyYAML',
        'dotenv': 'python-dotenv',
        'langchain': 'langchain',
        'langchain_community': 'langchain-community',
        'torch': 'torch',
        'sentence_transformers': 'sentence-transformers',
        'chromadb': 'chromadb',
    }
    
    missing = []
    for import_name, package_name in required_packages.items():
        try:
            __import__(import_name if import_name != 'dotenv' else 'dotenv')
        except ImportError:
            missing.append(package_name)
    
    if missing:
        print(f"❌ Missing required packages: {', '.join(missing)}")
        print(f"\nInstall with:")
        print(f"  conda install -c conda-forge {' '.join(missing)}")
        print(f"  # OR")
        print(f"  pip install {' '.join(missing)}")
        sys.exit(1)

check_dependencies()

# Now import everything
# NOTE: Using langchain 0.1.0 built-in modules. See TECHNICAL_NOTES.md for upgrade path.
import yaml
from dotenv import load_dotenv
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyPDFLoader, DirectoryLoader
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma
from langchain.schema import Document
import torch

load_dotenv()

def load_config():
    """Load configuration from YAML file."""
    config_path = 'config.yaml'
    if not os.path.exists(config_path):
        print(f"❌ Config file not found: {config_path}")
        print("Creating default config.yaml...")
        create_default_config()
    
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)

def create_default_config():
    """Create a default config.yaml if it doesn't exist."""
    default_config = """# Local LLM Configuration
llm:
  model_name: "mistralai/Mistral-7B-Instruct-v0.2"
  device: "cuda"
  load_in_8bit: true
  max_length: 2048
  temperature: 0.7
  
# Embedding Model Configuration
embeddings:
  model_name: "sentence-transformers/all-MiniLM-L6-v2"
  device: "cuda"

# Vector Store Configuration
vector_store:
  type: "chroma"
  persist_directory: "./vector_store"
  collection_name: "farming_docs"
  
# Chunking Configuration
chunking:
  chunk_size: 1000
  chunk_overlap: 200
  
# Retrieval Configuration
retrieval:
  top_k: 5
  similarity_threshold: 0.3

# System Prompt
master_prompt: |
  You are a helpful farming assistant specializing in natural farming practices and plant nutrition.
  Answer questions based on the provided context.
"""
    
    with open('config.yaml', 'w') as f:
        f.write(default_config)
    print("✅ Created default config.yaml")

def load_markdown_documents(md_directory="./data"):
    """Load markdown files and convert to documents."""
    md_path = Path(md_directory)
    
    if not md_path.exists():
        print(f"⚠️  Markdown directory does not exist: {md_directory}")
        print(f"   Creating directory...")
        md_path.mkdir(parents=True, exist_ok=True)
        return []
    
    md_files = list(md_path.glob("**/*.md"))
    
    if not md_files:
        print(f"⚠️  No markdown files found in {md_directory}")
        return []
    
    print(f"Found {len(md_files)} markdown files")
    documents = []
    
    for md_file in md_files:
        print(f"  Loading: {md_file.name}")
        try:
            # Read the markdown file
            with open(md_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Split by headers or bullet points for better chunking
            lines = content.split('\n')
            current_section = ""
            current_header = ""
            
            for line in lines:
                # Track current section header
                if line.startswith('##'):
                    # Save previous section
                    if current_section.strip():
                        doc = Document(
                            page_content=current_section.strip(),
                            metadata={
                                "source": str(md_file),
                                "file_name": md_file.name,
                                "section": current_header,
                                "type": "markdown"
                            }
                        )
                        documents.append(doc)
                    
                    current_header = line.replace('##', '').strip()
                    current_section = line + '\n'
                elif line.startswith('# '):
                    # Main title, skip or use as context
                    continue
                elif line.startswith('-'):
                    # Bullet point - each is a separate document for better retrieval
                    sentence = line.replace('-', '').strip()
                    if sentence:
                        doc = Document(
                            page_content=sentence,
                            metadata={
                                "source": str(md_file),
                                "file_name": md_file.name,
                                "section": current_header,
                                "type": "nutrient_fact"
                            }
                        )
                        documents.append(doc)
                else:
                    current_section += line + '\n'
            
            # Add last section
            if current_section.strip():
                doc = Document(
                    page_content=current_section.strip(),
                    metadata={
                        "source": str(md_file),
                        "file_name": md_file.name,
                        "section": current_header,
                        "type": "markdown"
                    }
                )
                documents.append(doc)
                
        except Exception as e:
            print(f"  ⚠️  Error loading {md_file}: {e}")
    
    return documents

def load_pdf_documents(pdf_directory="./data/pdfs"):
    """Load PDF documents."""
    pdf_path = Path(pdf_directory)
    
    if not pdf_path.exists():
        print(f"⚠️  PDF directory does not exist: {pdf_directory}")
        print(f"   Creating directory...")
        pdf_path.mkdir(parents=True, exist_ok=True)
        return []
    
    pdf_files = list(pdf_path.glob("**/*.pdf"))
    
    if not pdf_files:
        print(f"⚠️  No PDF files found in {pdf_directory}")
        return []
    
    print(f"Found {len(pdf_files)} PDF files")
    
    try:
        loader = DirectoryLoader(
            pdf_directory,
            glob="**/*.pdf",
            loader_cls=PyPDFLoader,
            show_progress=True
        )
        
        print("Loading PDF documents...")
        documents = loader.load()
        
        # Add metadata
        for doc in documents:
            doc.metadata["type"] = "pdf"
        
        return documents
    except Exception as e:
        print(f"⚠️  Error loading PDFs: {e}")
        return []

def index_documents(
    pdf_directory="./data/pdfs",
    md_directory="./data",
    force_reindex=False
):
    """Index all PDFs and Markdown files to local vector store."""
    
    config = load_config()
    
    # Check if vector store already exists
    persist_dir = config['vector_store']['persist_directory']
    if os.path.exists(persist_dir) and not force_reindex:
        print(f"✅ Vector store already exists at {persist_dir}")
        response = input("Do you want to reindex? (y/n): ")
        if response.lower() != 'y':
            print("Using existing vector store.")
            return
    
    print("Starting document indexing...")
    print("=" * 60)
    
    # Load documents from multiple sources
    all_documents = []
    
    # Load markdown files
    print("\n--- Loading Markdown Files ---")
    md_docs = load_markdown_documents(md_directory)
    all_documents.extend(md_docs)
    print(f"Loaded {len(md_docs)} markdown chunks")
    
    # Load PDF files
    print("\n--- Loading PDF Files ---")
    pdf_docs = load_pdf_documents(pdf_directory)
    all_documents.extend(pdf_docs)
    print(f"Loaded {len(pdf_docs)} PDF pages")
    
    if not all_documents:
        print("\n" + "=" * 60)
        print("❌ No documents found to index!")
        print(f"   PDF directory: {pdf_directory}")
        print(f"   Markdown directory: {md_directory}")
        print("\nMake sure you have:")
        print("  1. Converted your CSV to markdown using convert_csv_to_markdown.py")
        print("  2. Placed the markdown file in the data/ directory")
        print("  3. OR added PDF files to data/pdfs/")
        print("=" * 60)
        return
    
    print(f"\n✅ Total documents loaded: {len(all_documents)}")
    
    # Split PDF documents into chunks (markdown already chunked)
    print("\nSplitting PDF documents into chunks...")
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=config['chunking']['chunk_size'],
        chunk_overlap=config['chunking']['chunk_overlap'],
        length_function=len,
        separators=["\n\n", "\n", " ", ""]
    )
    
    # Only chunk PDFs, keep markdown as-is
    pdf_chunks = []
    md_chunks = []
    
    for doc in all_documents:
        if doc.metadata.get("type") == "pdf":
            pdf_chunks.extend(text_splitter.split_documents([doc]))
        else:
            md_chunks.append(doc)
    
    # Combine all chunks
    all_chunks = pdf_chunks + md_chunks
    
    print(f"  - PDF chunks: {len(pdf_chunks)}")
    print(f"  - Markdown chunks: {len(md_chunks)}")
    print(f"  - Total chunks: {len(all_chunks)}")
    
    # Initialize embeddings
    print(f"\nLoading embedding model: {config['embeddings']['model_name']}")
    device = config['embeddings']['device'] if torch.cuda.is_available() else 'cpu'
    print(f"Using device: {device}")
    
    if device == 'cpu' and config['embeddings']['device'] == 'cuda':
        print("⚠️  CUDA not available, falling back to CPU")
        print("   This will be slower but will work fine.")
    
    try:
        embeddings = HuggingFaceEmbeddings(
            model_name=config['embeddings']['model_name'],
            model_kwargs={'device': device},
            encode_kwargs={'normalize_embeddings': True}
        )
        print("✅ Embedding model loaded")
    except Exception as e:
        print(f"❌ Error loading embedding model: {e}")
        print("\nTrying alternative model...")
        embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/all-MiniLM-L6-v2",
            model_kwargs={'device': 'cpu'},
            encode_kwargs={'normalize_embeddings': True}
        )
        print("✅ Loaded fallback model on CPU")
    
    # Create vector store
    print("\nCreating vector store (this may take a while)...")
    print("⏳ Embedding documents and building index...")
    
    try:
        vectorstore = Chroma.from_documents(
            documents=all_chunks,
            embedding=embeddings,
            collection_name=config['vector_store']['collection_name'],
            persist_directory=persist_dir
        )
        
        print("\n" + "=" * 60)
        print("✅ INDEXING COMPLETE!")
        print("=" * 60)
        print(f"\nVector store saved to: {persist_dir}")
        print(f"\nIndexing Summary:")
        print(f"  - Total chunks indexed: {len(all_chunks)}")
        print(f"  - PDF chunks: {len(pdf_chunks)}")
        print(f"  - Markdown chunks: {len(md_chunks)}")
        print(f"  - Nutrient facts: {sum(1 for d in md_chunks if d.metadata.get('type') == 'nutrient_fact')}")
        print("\n✅ You can now run the chat application!")
        print("=" * 60)
    except Exception as e:
        print(f"\n❌ Error creating vector store: {e}")
        print("\nTroubleshooting:")
        print("  1. Make sure you have enough disk space")
        print("  2. Check permissions on the current directory")
        print("  3. Try running with --force flag to recreate")
        raise

def test_retrieval(query="What nutrients does okra contain?"):
    """Test the indexed vector store with a sample query."""
    print("\n" + "=" * 60)
    print("--- Testing Retrieval ---")
    print("=" * 60)
    print(f"Query: {query}")
    
    config = load_config()
    persist_dir = config['vector_store']['persist_directory']
    
    if not os.path.exists(persist_dir):
        print("❌ Vector store not found. Run indexing first!")
        return
    
    # Load embeddings
    device = config['embeddings']['device'] if torch.cuda.is_available() else 'cpu'
    
    try:
        embeddings = HuggingFaceEmbeddings(
            model_name=config['embeddings']['model_name'],
            model_kwargs={'device': device},
            encode_kwargs={'normalize_embeddings': True}
        )
    except:
        embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/all-MiniLM-L6-v2",
            model_kwargs={'device': 'cpu'},
            encode_kwargs={'normalize_embeddings': True}
        )
    
    # Load vector store
    print("Loading vector store from disk...")
    vectorstore = Chroma(
        collection_name=config['vector_store']['collection_name'],
        embedding_function=embeddings,
        persist_directory=persist_dir
    )
    
    # Retrieve similar documents
    print("Searching for relevant documents...")
    results = vectorstore.similarity_search_with_score(query, k=5)
    
    print(f"\n✅ Found {len(results)} results:\n")
    for i, (doc, score) in enumerate(results, 1):
        print(f"{i}. [Similarity Score: {score:.4f}]")
        print(f"   Content: {doc.page_content[:150]}...")
        print(f"   Source: {doc.metadata.get('file_name', 'Unknown')}")
        print(f"   Type: {doc.metadata.get('type', 'Unknown')}")
        print()
    
    print("=" * 60)
    print("✅ Test complete! Your vector store is working correctly.")
    print("=" * 60)

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Index PDFs and Markdown into local ChromaDB vector store',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Index markdown files only
  python local_indexer.py --md-dir ./data
  
  # Index both PDFs and markdown
  python local_indexer.py --pdf-dir ./data/pdfs --md-dir ./data
  
  # Force reindexing
  python local_indexer.py --md-dir ./data --force
  
  # Index and test
  python local_indexer.py --md-dir ./data --test
        """
    )
    parser.add_argument('--pdf-dir', default='./data/pdfs', help='Directory containing PDFs')
    parser.add_argument('--md-dir', default='./data', help='Directory containing Markdown files')
    parser.add_argument('--force', action='store_true', help='Force reindexing')
    parser.add_argument('--test', action='store_true', help='Run test query after indexing')
    
    args = parser.parse_args()
    
    try:
        index_documents(args.pdf_dir, args.md_dir, args.force)
        
        if args.test:
            test_retrieval()
    except KeyboardInterrupt:
        print("\n\n❌ Indexing interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)