import 'package:cactus/cactus.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Service for managing RAG (Retrieval-Augmented Generation) operations
/// using CactusRAG with ObjectBox vector storage.
class RagService {
  CactusRAG? _rag;
  CactusLM? _lm;
  bool _isInitialized = false;
  bool _documentsLoaded = false;

  /// Chunking configuration matching Python app settings
  static const int chunkSize = 1000;
  static const int chunkOverlap = 200;

  /// Search configuration
  static const int defaultTopK = 3;
  static const double maxDistance = 1.5; // Lower = more similar (squared Euclidean)

  bool get isInitialized => _isInitialized;
  bool get documentsLoaded => _documentsLoaded;

  /// Initialize the RAG service with a reference to CactusLM for embeddings
  Future<void> initialize(CactusLM lm) async {
    if (_isInitialized) return;

    _lm = lm;
    _rag = CactusRAG();
    await _rag!.initialize();

    // Configure embedding generator using CactusLM
    _rag!.setEmbeddingGenerator((text) async {
      final result = await _lm!.generateEmbedding(text: text);
      return result.embeddings;
    });

    // Configure chunking to match Python app settings
    _rag!.setChunking(chunkSize: chunkSize, chunkOverlap: chunkOverlap);

    _isInitialized = true;
  }

  /// Load the knowledge base from bundled assets
  Future<void> loadKnowledgeBase({
    required void Function(double progress, String status) onProgress,
  }) async {
    if (!_isInitialized) {
      throw RagServiceException('RAG not initialized. Call initialize first.');
    }

    if (_documentsLoaded) {
      onProgress(1.0, 'Knowledge base already loaded');
      return;
    }

    onProgress(0.0, 'Loading knowledge base...');

    // Check if documents are already stored
    final existingDocs = await _rag!.getAllDocuments();
    if (existingDocs.isNotEmpty) {
      _documentsLoaded = true;
      onProgress(1.0, 'Knowledge base ready (${existingDocs.length} documents)');
      return;
    }

    // Load from bundled asset
    onProgress(0.1, 'Reading knowledge base file...');
    final content = await rootBundle.loadString('assets/knowledge/nutrients_knowledge.md');

    onProgress(0.3, 'Processing and chunking document...');
    await _rag!.storeDocument(
      fileName: 'nutrients_knowledge.md',
      filePath: 'assets/knowledge/nutrients_knowledge.md',
      content: content,
      fileSize: content.length,
    );

    _documentsLoaded = true;
    onProgress(1.0, 'Knowledge base loaded successfully');
  }

  /// Search for relevant context given a query
  Future<String> searchContext(String query) async {
    if (!_isInitialized) {
      throw RagServiceException('RAG not initialized. Call initialize first.');
    }

    if (!_documentsLoaded) {
      return ''; // No context available yet
    }

    final results = await _rag!.search(text: query, limit: defaultTopK);

    if (results.isEmpty) {
      return '';
    }

    // Filter by distance threshold and combine relevant chunks
    final relevantChunks = results
        .where((result) => result.distance <= maxDistance)
        .map((result) => result.chunk.content)
        .toList();

    if (relevantChunks.isEmpty) {
      return '';
    }

    return relevantChunks.join('\n\n---\n\n');
  }

  /// Search and return detailed results with metadata
  Future<List<SearchResult>> searchDetailed(String query, {int? limit}) async {
    if (!_isInitialized) {
      throw RagServiceException('RAG not initialized. Call initialize first.');
    }

    if (!_documentsLoaded) {
      return [];
    }

    final results = await _rag!.search(text: query, limit: limit ?? defaultTopK);

    return results
        .where((result) => result.distance <= maxDistance)
        .map((result) => SearchResult(
              content: result.chunk.content,
              distance: result.distance,
            ))
        .toList();
  }

  /// Store a custom document (for user-added knowledge)
  Future<void> storeDocument({
    required String fileName,
    required String content,
  }) async {
    if (!_isInitialized) {
      throw RagServiceException('RAG not initialized. Call initialize first.');
    }

    await _rag!.storeDocument(
      fileName: fileName,
      filePath: fileName,
      content: content,
      fileSize: content.length,
    );
  }

  /// Get count of stored documents
  Future<int> getDocumentCount() async {
    if (!_isInitialized) return 0;
    final docs = await _rag!.getAllDocuments();
    return docs.length;
  }

  /// Clear all stored documents (useful for reindexing)
  Future<void> clearDocuments() async {
    if (!_isInitialized) return;
    final docs = await _rag!.getAllDocuments();
    for (final doc in docs) {
      await _rag!.deleteDocument(doc.id);
    }
    _documentsLoaded = false;
  }

  /// Release resources
  Future<void> dispose() async {
    if (_rag != null) {
      await _rag!.close();
    }
    _rag = null;
    _lm = null;
    _isInitialized = false;
    _documentsLoaded = false;
  }
}

/// Result from a RAG search operation
class SearchResult {
  final String content;
  final double distance;

  SearchResult({
    required this.content,
    required this.distance,
  });

  /// Convenience getter for similarity score (inverted distance)
  /// Higher = more similar
  double get similarity => 1.0 / (1.0 + distance);
}

/// Exception thrown by RagService
class RagServiceException implements Exception {
  final String message;

  RagServiceException(this.message);

  @override
  String toString() => 'RagServiceException: $message';
}
