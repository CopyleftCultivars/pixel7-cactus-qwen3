# Technical Notes & Decisions

This document tracks important technical decisions and configuration notes for this project.

---

## Langchain Version & Import Structure

**Date:** 2026-01-27
**Decision:** Use langchain 0.1.0 with built-in modules

### Context
The project uses `langchain==0.1.0` which has a different module structure than newer versions (0.2+).

### Key Points

1. **langchain 0.1.0 includes these modules built-in:**
   - `langchain.text_splitter` - Contains `RecursiveCharacterTextSplitter`
   - `langchain.schema` - Contains `Document` class
   - These are part of the main `langchain` package

2. **DO NOT use these packages with langchain 0.1.0:**
   - `langchain-core` - Only compatible with langchain 0.2+
   - `langchain-text-splitters` - Only compatible with langchain 0.2+
   - These will cause dependency conflicts

3. **Current Working Imports** (see [local_indexer.py](local_indexer.py)):
   ```python
   from langchain.text_splitter import RecursiveCharacterTextSplitter
   from langchain_community.document_loaders import PyPDFLoader, DirectoryLoader
   from langchain_community.embeddings import HuggingFaceEmbeddings
   from langchain_community.vectorstores import Chroma
   from langchain.schema import Document
   ```

4. **Dependencies** (see [requirements.txt](requirements.txt)):
   ```
   langchain==0.1.0
   langchain-community==0.0.10
   ```

### If Upgrading Langchain in the Future

When upgrading to langchain 0.2+, you'll need to:

1. Update [requirements.txt](requirements.txt):
   ```
   langchain>=0.2.0
   langchain-community>=0.2.0
   langchain-core>=0.2.0
   langchain-text-splitters>=0.2.0
   ```

2. Update imports in [local_indexer.py](local_indexer.py):
   ```python
   from langchain_text_splitters import RecursiveCharacterTextSplitter
   from langchain_core.documents import Document
   ```

3. Test thoroughly as the API may have other breaking changes.

---

## Future Refactoring Notes

- Consider upgrading langchain stack when ready for major refactoring
- Evaluate alternatives to langchain if dependency management becomes too complex
- Document any other version-specific quirks here
