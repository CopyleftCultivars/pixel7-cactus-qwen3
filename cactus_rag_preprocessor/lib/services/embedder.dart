import 'dart:convert';
import 'package:http/http.dart' as http;

/// Required embedding dimensions (must match ObjectBox schema @HnswIndex)
const int requiredEmbeddingDimensions = 1024;

/// Abstract embedder interface.
abstract class Embedder {
  /// Initialize and validate embedding dimensions.
  /// Throws if embedding model produces wrong dimension count.
  Future<void> initialize();

  /// Generate embedding for text.
  Future<List<double>> embed(String text);

  /// Get the validated embedding dimensions.
  int get dimensions;

  Future<void> close();
}

/// HTTP-based embedder for Ollama API.
class HttpEmbedder implements Embedder {
  final String apiUrl;
  final String model;
  final http.Client _client;
  int? _dimensions;
  bool _initialized = false;

  HttpEmbedder({
    required this.apiUrl,
    required this.model,
  }) : _client = http.Client();

  @override
  int get dimensions {
    if (!_initialized) {
      throw EmbedderException('Embedder not initialized. Call initialize() first.');
    }
    return _dimensions!;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Test embed to validate dimensions
    const testText = 'dimension validation test';
    final testEmbedding = await _doEmbed(testText);
    _dimensions = testEmbedding.length;

    if (_dimensions != requiredEmbeddingDimensions) {
      throw EmbedderException(
        'Embedding dimension mismatch!\n'
        '  Model "$model" produces $_dimensions dimensions\n'
        '  Schema requires $requiredEmbeddingDimensions dimensions\n'
        '  Use a compatible embedding model (e.g., mxbai-embed-large for 1024 dims)',
      );
    }

    _initialized = true;
  }

  @override
  Future<List<double>> embed(String text) async {
    if (!_initialized) {
      throw EmbedderException('Embedder not initialized. Call initialize() first.');
    }
    return _doEmbed(text);
  }

  Future<List<double>> _doEmbed(String text) async {
    final uri = Uri.parse('$apiUrl/api/embeddings');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'prompt': text,
      }),
    );

    if (response.statusCode != 200) {
      throw EmbedderException(
        'Embedding request failed: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (!data.containsKey('embedding')) {
      throw EmbedderException('Response missing "embedding" field: $data');
    }

    final embedding = (data['embedding'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    return embedding;
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

class EmbedderException implements Exception {
  final String message;
  EmbedderException(this.message);

  @override
  String toString() => 'EmbedderException: $message';
}
