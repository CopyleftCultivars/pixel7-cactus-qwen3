import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cactus/cactus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Service for managing RAG (Retrieval-Augmented Generation) operations
/// using CactusRAG with ObjectBox vector storage.
class RagService {
  CactusRAG? _rag;
  CactusLM? _lm;
  bool _isInitialized = false;
  bool _documentsLoaded = false;

  /// Cache for pre-computed embeddings (keyed by content hash)
  final Map<String, List<double>> _embeddingCache = {};
  bool _precomputedEmbeddingsLoaded = false;
  int _cacheHits = 0;
  int _cacheMisses = 0;

  /// Chunking configuration matching Python app settings
  static const int chunkSize = 1000;
  static const int chunkOverlap = 200;

  /// Search configuration
  static const int defaultTopK = 3;
  static const double maxDistance = 1.5; // Lower = more similar (squared Euclidean)

  /// Path for pre-computed embeddings file (pushed via ADB)
  static const String precomputedEmbeddingsFileName = 'embeddings_precomputed.json';

  bool get isInitialized => _isInitialized;
  bool get documentsLoaded => _documentsLoaded;
  bool get precomputedEmbeddingsLoaded => _precomputedEmbeddingsLoaded;
  int get embeddingCacheHits => _cacheHits;
  int get embeddingCacheMisses => _cacheMisses;

  /// Initialize the RAG service with a reference to CactusLM for embeddings
  Future<void> initialize(CactusLM lm) async {
    if (_isInitialized) return;

    _lm = lm;
    _rag = CactusRAG();
    await _rag!.initialize();

    // Configure embedding generator with caching support
    _rag!.setEmbeddingGenerator(_cachedEmbeddingGenerator);

    // Configure chunking to match Python app settings
    _rag!.setChunking(chunkSize: chunkSize, chunkOverlap: chunkOverlap);

    _isInitialized = true;
  }

  /// Embedding generator that checks cache before generating on-device
  Future<List<double>> _cachedEmbeddingGenerator(String text) async {
    // Compute hash of the text content
    final contentHash = _computeContentHash(text);

    // Check if we have a pre-computed embedding
    if (_embeddingCache.containsKey(contentHash)) {
      _cacheHits++;
      developer.log(
        'Cache HIT for hash $contentHash (hits: $_cacheHits, misses: $_cacheMisses)',
        name: 'RagService.cache',
      );
      return _embeddingCache[contentHash]!;
    }

    // Generate embedding on-device
    _cacheMisses++;
    developer.log(
      'Cache MISS for hash $contentHash - generating on-device (hits: $_cacheHits, misses: $_cacheMisses)',
      name: 'RagService.cache',
    );

    final result = await _lm!.generateEmbedding(text: text);
    return result.embeddings;
  }

  /// Compute SHA256 hash of content (first 16 chars)
  String _computeContentHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Load pre-computed embeddings from file on device.
  /// Call this after initialize() but before loadKnowledgeBase().
  /// Returns true if pre-computed embeddings were loaded successfully.
  Future<bool> loadPrecomputedEmbeddings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$precomputedEmbeddingsFileName');

      if (!await file.exists()) {
        developer.log(
          'Pre-computed embeddings file not found at ${file.path}',
          name: 'RagService.precompute',
        );
        return false;
      }

      developer.log(
        'Loading pre-computed embeddings from ${file.path}',
        name: 'RagService.precompute',
      );

      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate structure
      if (!data.containsKey('chunks')) {
        developer.log(
          'Invalid embeddings file: missing "chunks" key',
          name: 'RagService.precompute',
        );
        return false;
      }

      final chunks = data['chunks'] as List<dynamic>;
      _embeddingCache.clear();

      for (final chunk in chunks) {
        final chunkMap = chunk as Map<String, dynamic>;
        final contentHash = chunkMap['content_hash'] as String;
        final embeddingList = chunkMap['embedding'] as List<dynamic>;
        final embedding = embeddingList.cast<num>().map((n) => n.toDouble()).toList();

        _embeddingCache[contentHash] = embedding;
      }

      _precomputedEmbeddingsLoaded = true;
      developer.log(
        'Loaded ${_embeddingCache.length} pre-computed embeddings',
        name: 'RagService.precompute',
      );

      return true;
    } catch (e) {
      developer.log(
        'Error loading pre-computed embeddings: $e',
        name: 'RagService.precompute',
      );
      return false;
    }
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

  // ============================================================
  // DEBUG METHODS - For embedding compatibility testing
  // ============================================================

  /// Test phrases for embedding comparison with host-side generator
  static const List<String> debugTestPhrases = [
    'What is nitrogen fixation?',
    'How do I make compost tea?',
    'natural farming fertilizer',
    'potassium deficiency symptoms',
  ];

  /// Generate embedding for a single text and return raw values.
  /// Used for debugging and comparing with host-side embeddings.
  Future<EmbeddingDebugResult> generateEmbeddingDebug(String text) async {
    if (!_isInitialized || _lm == null) {
      throw RagServiceException('RAG not initialized. Call initialize first.');
    }

    final result = await _lm!.generateEmbedding(text: text);
    final embeddings = result.embeddings;

    developer.log(
      'Embedding generated: dim=${embeddings.length}, '
      'first5=${embeddings.take(5).toList()}, '
      'last5=${embeddings.skip(embeddings.length - 5).toList()}',
      name: 'RagService.debug',
    );

    return EmbeddingDebugResult(
      text: text,
      embedding: embeddings,
      dimension: embeddings.length,
    );
  }

  /// Generate embeddings for all test phrases and return as JSON string.
  /// Copy this output to embeddings_cactus.json for comparison with
  /// the host-side llama-cpp-python embeddings.
  Future<String> exportEmbeddingsJson() async {
    if (!_isInitialized || _lm == null) {
      throw RagServiceException('RAG not initialized. Call initialize first.');
    }

    developer.log('Starting embedding export...', name: 'RagService.debug');

    final results = <Map<String, dynamic>>[];

    for (final phrase in debugTestPhrases) {
      developer.log('Generating embedding for: $phrase', name: 'RagService.debug');
      final result = await generateEmbeddingDebug(phrase);
      results.add({
        'text': result.text,
        'dimension': result.dimension,
        'embedding': result.embedding,
      });
    }

    final output = {
      'generator': 'CactusLM',
      'model': 'qwen3-0.6',
      'embeddings': results,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(output);

    developer.log(
      'Export complete. JSON length: ${jsonString.length}',
      name: 'RagService.debug',
    );

    return jsonString;
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

/// Debug result containing raw embedding data for comparison testing
class EmbeddingDebugResult {
  final String text;
  final List<double> embedding;
  final int dimension;

  EmbeddingDebugResult({
    required this.text,
    required this.embedding,
    required this.dimension,
  });
}

/// Exception thrown by RagService
class RagServiceException implements Exception {
  final String message;

  RagServiceException(this.message);

  @override
  String toString() => 'RagServiceException: $message';
}
