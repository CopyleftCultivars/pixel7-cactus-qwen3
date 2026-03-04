import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'model_service.dart';

/// Ollama-compatible HTTP benchmark server.
///
/// Exposes `POST /api/generate` on [port] (default 11435) so that external
/// evaluation harnesses (evaluate.py --ollama-url, OpenCompass) can query the
/// on-device Cactus model as if it were a local Ollama instance.
///
/// Request body (JSON):
/// ```json
/// { "model": "...", "prompt": "...", "system": "...",
///   "stream": false, "options": {"temperature": 0} }
/// ```
/// Response body (JSON):
/// ```json
/// { "model": "...", "response": "...", "done": true }
/// ```
///
/// Usage:
/// ```dart
/// final server = BenchmarkServer(modelService);
/// await server.start();   // call after model is initialised
/// // ...
/// server.stop();
/// ```
class BenchmarkServer {
  static const int defaultPort = 11435;

  final ModelService _modelService;
  HttpServer? _server;

  BenchmarkServer(this._modelService);

  bool get isRunning => _server != null;

  Future<void> start({int port = defaultPort}) async {
    if (_server != null) return; // already running

    final router = Router();
    router.post('/api/generate', _handleGenerate);
    // Ollama health check used by some clients
    router.get('/api/tags', _handleTags);

    final handler = const Pipeline().addHandler(router);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );

    print('[BenchmarkServer] Listening on port $port');
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
    print('[BenchmarkServer] Stopped');
  }

  Future<Response> _handleGenerate(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final rawPrompt = (data['prompt'] as String?) ?? '';
      final system = data['system'] as String?;

      // Prepend /no_think to disable Qwen3 chain-of-thought for benchmark
      // evaluation. Thinking mode generates hundreds of tokens before the
      // answer, causing timeouts on mobile hardware.
      final prompt = '/no_think\n$rawPrompt';

      final response = await _modelService.generateRaw(
        prompt: prompt,
        systemPrompt: system,
        maxTokens: ModelService.defaultMaxTokens,
      );

      return Response.ok(
        jsonEncode({
          'model': ModelService.modelSlug,
          'response': response,
          'done': true,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString(), 'done': true}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _handleTags(Request request) async {
    // Minimal Ollama /api/tags response so clients can verify the server is up.
    return Response.ok(
      jsonEncode({
        'models': [
          {'name': ModelService.modelSlug}
        ]
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
