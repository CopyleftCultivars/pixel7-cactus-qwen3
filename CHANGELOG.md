# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Update Flutter app to load pre-built ObjectBox database instead of re-chunking (#26)
- Implement CLI entry point with argument parsing and document processing (#25)
- Implement Chunker, Embedder, and RagDatabase services (#24)
- Implement Document and DocumentChunk ObjectBox entities matching cactus-flutter schema (#23)
- Create cactus_rag_preprocessor Dart CLI project with ObjectBox dependencies (#22)
- Add host-side embedding generation for CactusRAG (#16)
- Port calculator tool and agentic mode (#8)

### Fixed

### Changed
- Convert Natural Farming Chat to Flutter Android App (#1)
- Test on Pixel 7 device (#11)
- Fix RAG to use pre-computed embeddings without re-chunking on device (#21)
- Fix RAG to load pre-computed embeddings via CactusRAG API instead of ObjectBox database (#27)
- Add ADB script to push pre-built RAG database to device (#14)
- Add pre-computed RAG index to speed up first launch (#13)
- Build release APK for Pixel 7 (#12)
- Modify Flutter RAG service to load pre-computed embeddings (#20)
- Create host-side embedding generator script (#19)
- Add debug logging to Flutter RAG service for embedding comparison (#18)
- Create embedding compatibility test script (#17)
- Implement state management and persistence (#10)
- Implement response generation and cleaning logic (#9)
- Build Flutter chat UI (#7)
- Migrate knowledge base documents to mobile format (#6)
- Implement CactusRAG for vector storage and retrieval (#5)
- Implement CactusLM model loading and initialization (#4)
- Configure Android manifest and permissions (#3)
- Install Flutter SDK and set up development environment (#2)
