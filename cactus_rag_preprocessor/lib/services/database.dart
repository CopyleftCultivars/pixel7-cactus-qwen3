import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;

import '../models/document.dart';
import '../models/document_chunk.dart';
import '../objectbox.g.dart';

/// Database service for ObjectBox operations.
class RagDatabase {
  Store? _store;
  Box<Document>? _documentBox;
  Box<DocumentChunk>? _chunkBox;
  String? _directory;

  bool get isOpen => _store != null;
  String? get directory => _directory;

  /// Open the ObjectBox database at the specified directory.
  Future<void> open(String directory) async {
    _directory = directory;
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _store = await openStore(directory: directory);
    _documentBox = _store!.box<Document>();
    _chunkBox = _store!.box<DocumentChunk>();
  }

  /// Store multiple documents in a single transaction for efficiency.
  /// This is 10-50x faster than individual puts.
  Future<void> storeDocumentsBatched(List<DocumentData> documents) async {
    if (!isOpen) {
      throw DatabaseException('Database not open');
    }

    _store!.runInTransaction(TxMode.write, () {
      for (final docData in documents) {
        _storeDocumentSync(docData);
      }
    });
  }

  /// Store a single document (use storeDocumentsBatched for multiple docs).
  Future<Document> storeDocument({
    required String fileName,
    required String filePath,
    required String content,
    required List<String> chunks,
    required List<List<double>> embeddings,
    int? fileSize,
  }) async {
    if (!isOpen) {
      throw DatabaseException('Database not open');
    }

    final docData = DocumentData(
      fileName: fileName,
      filePath: filePath,
      content: content,
      chunks: chunks,
      embeddings: embeddings,
      fileSize: fileSize,
    );

    return _store!.runInTransaction(TxMode.write, () {
      return _storeDocumentSync(docData);
    });
  }

  Document _storeDocumentSync(DocumentData data) {
    if (data.chunks.length != data.embeddings.length) {
      throw DatabaseException(
        'Chunks and embeddings count mismatch: ${data.chunks.length} vs ${data.embeddings.length}',
      );
    }

    // Compute file hash
    final fileHash = sha256.convert(utf8.encode(data.content)).toString();

    // Create document
    final document = Document(
      fileName: data.fileName,
      filePath: data.filePath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      fileSize: data.fileSize ?? data.content.length,
      fileHash: fileHash,
    );

    // Create chunks with embeddings
    for (var i = 0; i < data.chunks.length; i++) {
      final chunk = DocumentChunk(
        content: data.chunks[i],
        embeddings: data.embeddings[i],
      );
      chunk.document.target = document;
      document.chunks.add(chunk);
    }

    // Store document (cascades to chunks via ToMany relation)
    _documentBox!.put(document);

    return document;
  }

  /// Get all documents.
  List<Document> getAllDocuments() {
    if (!isOpen) return [];
    return _documentBox!.getAll();
  }

  /// Get total chunk count.
  int getChunkCount() {
    if (!isOpen) return 0;
    return _chunkBox!.count();
  }

  /// Close the database and optionally clean up lock file for bundling.
  Future<void> close({bool cleanupLockFile = false}) async {
    final dir = _directory;
    _store?.close();
    _store = null;
    _documentBox = null;
    _chunkBox = null;

    if (cleanupLockFile && dir != null) {
      await deleteLockFile(dir);
    }
  }

  /// Delete lock.mdb file from the database directory.
  /// CRITICAL: Must be called before bundling database for mobile deployment.
  /// The lock file causes DbLockedException if bundled with app assets.
  static Future<void> deleteLockFile(String directory) async {
    final lockFile = File(p.join(directory, 'lock.mdb'));
    if (await lockFile.exists()) {
      await lockFile.delete();
    }
  }
}

/// Data transfer object for batched document storage.
class DocumentData {
  final String fileName;
  final String filePath;
  final String content;
  final List<String> chunks;
  final List<List<double>> embeddings;
  final int? fileSize;

  DocumentData({
    required this.fileName,
    required this.filePath,
    required this.content,
    required this.chunks,
    required this.embeddings,
    this.fileSize,
  });
}

class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
