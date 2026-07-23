import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cactus/cactus.dart';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

/// Service for managing CactusLM model operations
class ModelService {
  CactusLM? _lm;
  bool _isInitialized = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  /// Default maximum tokens for completions (increased from 512 to prevent truncation)
  static const int defaultMaxTokens = 2048;

  // Cactus INT4 bundle converted from the v5 Qwen3 checkpoint and published
  // in the CopyleftCultivars/localNFchatbot-cactus Hugging Face repository.
  static const String modelSlug = 'qwen3-nf-v5-cact-int4';

  static const String _modelDownloadUrl =
      'https://huggingface.co/CopyleftCultivars/localNFchatbot-cactus/resolve/main/qwen3-nf-v5-cact-int4.zip';
  static const String systemPrompt = '''
You are a helpful farming assistant specializing in natural farming practices.
Answer questions based on the provided context. If you don't know the answer,
say so honestly. Provide practical, actionable advice when possible.''';

  /// Farming tools available for function calling
  static final List<CactusTool> farmingTools = [
    CactusTool(
      name: 'npk_lookup',
      description:
          'Look up the mineral profile of a plant including calcium, iron, potassium, phosphorus, magnesium, and other minerals across different plant parts (leaf, fruit, seed, root, etc.)',
      parameters: ToolParametersSchema(
        properties: {
          'plant': ToolParameter(
            type: 'string',
            description: 'Common name or scientific name of the plant (e.g., Tomato, Okra, Solanum lycopersicum)',
            required: true,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'calculate',
      description:
          'Perform mathematical calculations for fertilizer amounts, nutrient ratios, coverage area, or dilution rates',
      parameters: ToolParametersSchema(
        properties: {
          'expression': ToolParameter(
            type: 'string',
            description:
                'Mathematical expression to evaluate (e.g., "100 * 0.05" for 5% of 100)',
            required: true,
          ),
          'context': ToolParameter(
            type: 'string',
            description:
                'Optional context describing what the calculation is for',
            required: false,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'local_fertilizer_plants',
      description:
          'Create an organic fertilizer formulation using plants available '
          'in the user\'s region. Returns a complete blend with percentages, '
          'NPK values, and preparation instructions.',
      parameters: ToolParametersSchema(
        properties: {
          'location': ToolParameter(
            type: 'string',
            description:
                'Country or region name (e.g., "Kenya", "California", "France")',
            required: true,
          ),
          'nutrient': ToolParameter(
            type: 'string',
            description:
                'Target nutrient or growth stage: "nitrogen" (leafy/vegetative), '
                '"phosphorus" (flowering/roots), "potassium" (fruiting), '
                '"balanced", "vegetative", "flowering", "fruiting", or "seedling"',
            required: true,
          ),
        },
      ),
    ),
  ];

  bool get isInitialized => _isInitialized;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get downloadStatus => _downloadStatus;

  /// Get the underlying CactusLM instance for use by RagService
  /// Returns null if model is not downloaded yet
  CactusLM? get lm => _lm;

  /// Download the fine-tuned model directly from HuggingFace storage.
  /// Bypasses Cactus's Supabase slug registry since our model is not
  /// a built-in Cactus model.
  Future<void> downloadModel({
    required void Function(double progress, String status) onProgress,
  }) async {
    if (_isDownloading) return;

    _isDownloading = true;
    // NOTE: semantic tool filtering disabled - it tries to generate embeddings
    // using the chat model which causes hangs. With 3 tools, keyword-based
    // filtering could help but isn't critical yet.
    _lm = CactusLM(
      enableToolFiltering: false,
    );

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelFolder = Directory('${appDocDir.path}/models/$modelSlug');

      final configFile = File('${modelFolder.path}/config.txt');
      if (await configFile.exists()) {
        onProgress(1.0, 'Model already downloaded');
        return;
      }

      // Clean up any partial download before starting fresh
      if (await modelFolder.exists()) {
        await modelFolder.delete(recursive: true);
      }

      await modelFolder.create(recursive: true);

      // Download zip
      final zipPath = '${appDocDir.path}/models/$modelSlug.zip';
      final client = HttpClient();
      try {
        onProgress(0.0, 'Starting download...');
        final request = await client.getUrl(Uri.parse(_modelDownloadUrl));
        final response = await request.close();

        if (response.statusCode != 200) {
          throw ModelServiceException(
              'Download failed: HTTP ${response.statusCode}');
        }

        final contentLength = response.contentLength;
        final sink = File(zipPath).openWrite();
        int bytesReceived = 0;

        await for (final chunk in response) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          if (contentLength > 0) {
            // Reserve 0–0.85 for download, 0.85–1.0 for extraction
            final downloadProgress = (bytesReceived / contentLength) * 0.85;
            _downloadProgress = downloadProgress;
            _downloadStatus =
                'Downloaded ${bytesReceived ~/ (1024 * 1024)} MB...';
            onProgress(_downloadProgress, _downloadStatus);
          }
        }
        await sink.close();
      } finally {
        client.close();
      }

      // Extract zip directly into the model folder
      onProgress(0.85, 'Extracting model files...');
      final inputStream = InputFileStream(zipPath);
      try {
        final archive = ZipDecoder().decodeStream(inputStream);
        for (final file in archive) {
          if (!file.isFile) continue;
          final outPath = '${modelFolder.path}/${file.name}';
          await File(outPath).parent.create(recursive: true);
          final outStream = OutputFileStream(outPath);
          file.writeContent(outStream);
          outStream.closeSync();
        }
      } finally {
        inputStream.close();
      }

      await File(zipPath).delete();
      onProgress(1.0, 'Download complete');
    } finally {
      _isDownloading = false;
    }
  }

  /// Initialize the model for inference
  Future<void> initializeModel() async {
    if (_lm == null) {
      throw ModelServiceException('Model not downloaded. Call downloadModel first.');
    }

    if (_isInitialized) return;

    // Pass the published artifact slug explicitly — CactusInitParams defaults
    // to 'qwen3-0.6', which would point to the wrong model folder.
    try {
      await _lm!.initializeModel(params: CactusInitParams(model: modelSlug));
    } catch (e) {
      // Surface the native C++ error message for diagnosis
      final nativeError = _getLastNativeError();
      print('[MODEL_INIT_ERROR] Flutter exception: $e');
      print('[MODEL_INIT_ERROR] Native C++ error: $nativeError');
      rethrow;
    }
    _isInitialized = true;
  }

  /// Read the last error from libcactus.so via direct FFI
  static String _getLastNativeError() {
    try {
      final lib = DynamicLibrary.open(
        Platform.isAndroid ? 'libcactus.so' : 'cactus.framework/cactus',
      );
      final getLastError = lib
          .lookup<NativeFunction<Pointer<Utf8> Function()>>('cactus_get_last_error')
          .asFunction<Pointer<Utf8> Function()>();
      final ptr = getLastError();
      if (ptr.address == 0) return '(no error message)';
      return ptr.toDartString();
    } catch (e) {
      return '(could not read native error: $e)';
    }
  }

  /// Generate a completion with optional context and conversation history
  Future<CompletionResult> generateCompletion({
    required String question,
    String? context,
    bool agenticMode = false,
    List<ChatMessage>? conversationHistory,
  }) async {
    if (!_isInitialized) {
      throw ModelServiceException('Model not initialized. Call initializeModel first.');
    }

    final systemContent = _buildSystemContent(context, agenticMode);

    final messages = [
      ChatMessage(content: systemContent, role: 'system'),
      if (conversationHistory != null) ...conversationHistory,
      ChatMessage(content: question, role: 'user'),
    ];

    final result = await _lm!.generateCompletion(
      messages: messages,
      params: CactusCompletionParams(maxTokens: defaultMaxTokens),
    );

    if (!result.success) {
      throw ModelServiceException('Generation failed: ${result.response}');
    }

    final cleanedResponse = _cleanResponse(result.response);

    return CompletionResult(
      response: cleanedResponse,
      tokensPerSecond: result.tokensPerSecond,
    );
  }

  /// Generate a streaming completion
  Future<Stream<String>> generateCompletionStream({
    required String question,
    String? context,
    bool agenticMode = false,
  }) async {
    if (!_isInitialized) {
      throw ModelServiceException('Model not initialized. Call initializeModel first.');
    }

    final systemContent = _buildSystemContent(context, agenticMode);

    final messages = [
      ChatMessage(content: systemContent, role: 'system'),
      ChatMessage(content: question, role: 'user'),
    ];

    final streamedResult = await _lm!.generateCompletionStream(
      messages: messages,
      params: CactusCompletionParams(maxTokens: defaultMaxTokens),
    );

    return streamedResult.stream;
  }

  /// Generate a completion with tool calling support
  /// Returns both the response and any tool calls the model wants to make
  Future<CompletionResultWithTools> generateCompletionWithTools({
    required String question,
    String? context,
    List<CactusTool>? tools,
    List<ChatMessage>? conversationHistory,
  }) async {
    if (!_isInitialized) {
      throw ModelServiceException('Model not initialized. Call initializeModel first.');
    }

    final systemContent = _buildSystemContentForTools(context);
    final effectiveTools = tools ?? farmingTools;

    print('[TOOL_DEBUG] generateCompletionWithTools called');
    print('[TOOL_DEBUG] Question: $question');
    print('[TOOL_DEBUG] Context length: ${context?.length ?? 0}');
    print('[TOOL_DEBUG] History turns: ${conversationHistory?.length ?? 0}');
    print('[TOOL_DEBUG] Available tools: ${effectiveTools.map((t) => t.name).toList()}');

    final messages = [
      ChatMessage(content: systemContent, role: 'system'),
      if (conversationHistory != null) ...conversationHistory,
      ChatMessage(content: question, role: 'user'),
    ];

    print('[TOOL_DEBUG] Calling generateCompletion WITH tools...');
    final result = await _lm!.generateCompletion(
      messages: messages,
      params: CactusCompletionParams(
        maxTokens: defaultMaxTokens,
        tools: effectiveTools,
      ),
    );

    print('[TOOL_DEBUG] Generation success: ${result.success}');
    print('[TOOL_DEBUG] Raw response length: ${result.response.length}');
    print('[TOOL_DEBUG] Tool calls returned: ${result.toolCalls.length}');
    for (final tc in result.toolCalls) {
      print('[TOOL_DEBUG]   - Tool: ${tc.name}, Args: ${tc.arguments}');
    }

    if (!result.success) {
      throw ModelServiceException('Generation failed: ${result.response}');
    }

    final cleanedResponse = _cleanResponse(result.response);

    return CompletionResultWithTools(
      response: cleanedResponse,
      tokensPerSecond: result.tokensPerSecond,
      toolCalls: result.toolCalls,
    );
  }

  String _buildSystemContentForTools(String? context) {
    var content = systemPrompt;

    content += '''

You have access to tools for looking up plant nutrients, performing calculations, and creating fertilizer formulations.
When the user asks about NPK ratios or nutrient requirements, use npk_lookup.
When the user asks about making organic fertilizer:
- If they haven't specified their location, ask where they are farming.
- Once you know location and crop type, use local_fertilizer_plants to get a formulation.
- Choose the nutrient parameter based on growth stage: "nitrogen" for leafy greens or vegetative growth, "phosphorus" for flowering or root development, "potassium" for fruiting, "balanced" for general use, or "seedling" for transplants.
After receiving tool results, provide a helpful summary to the user.''';

    if (context != null && context.isNotEmpty) {
      content += '\n\nRelevant Context:\n$context';
    }

    return content;
  }

  String _buildSystemContent(String? context, bool agenticMode) {
    var content = systemPrompt;

    if (agenticMode) {
      content += '''

AGENTIC MODE:
You have access to a calculator. Use <calculate>expression</calculate> for math.
I will parse this tag, run the math, and return the result.
Make multiple iterations if necessary.''';
    }

    if (context != null && context.isNotEmpty) {
      content += '\n\nRelevant Context:\n$context';
    }

    return content;
  }

  /// Clean the response to remove prompt leakage and thinking tags
  String _cleanResponse(String response) {
    var cleaned = response;

    // Remove Qwen3 thinking tags and content
    cleaned = cleaned.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');

    // Remove prompt structure tags
    cleaned = cleaned.replaceAll(RegExp(r'\[/?CONTEXT\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[/?QUESTION\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[/?ANSWER\]'), '');

    // Remove common prompt leakage patterns
    final leakPatterns = [
      r'Previous conversation:.*?(?=\n\n|$)',
      r'Relevant knowledge:.*?(?=\n\n|$)',
      r'Current question:.*?(?=\n\n|$)',
      r'Please provide a helpful.*?(?=\n\n|$)',
      r'AGENTIC MODE:.*?(?=\n\n|$)',
      r'(You are|I am) a helpful farming assistant[^\n]*',
      r'USER:.*?ASSISTANT:',
    ];

    for (final pattern in leakPatterns) {
      cleaned = cleaned.replaceAll(
        RegExp(pattern, caseSensitive: false, dotAll: true),
        '',
      );
    }

    // Remove reasoning starts - truncate from these points
    final reasoningStarts = [
      RegExp(r"\n\s*Okay, let's see", caseSensitive: false),
      RegExp(r'\n\s*Let me think', caseSensitive: false),
      RegExp(r'\n\s*Wait, (the user|I should|maybe)', caseSensitive: false),
      RegExp(r'\n\s*My job is to', caseSensitive: false),
      RegExp(r'\n\s*I need to recall', caseSensitive: false),
      RegExp(r'\n\s*First, I need to', caseSensitive: false),
    ];

    for (final pattern in reasoningStarts) {
      final match = pattern.firstMatch(cleaned);
      if (match != null) {
        cleaned = cleaned.substring(0, match.start);
      }
    }

    // Remove prompt structure markers at start
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(ASSISTANT:|AI:|Response:)\s*', caseSensitive: false),
      '',
    );

    // Clean up excessive whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim();
  }

  /// Combined initialize method - downloads and initializes the model
  Future<void> initialize({
    required void Function(double progress, String status) onProgress,
  }) async {
    if (_isInitialized) return;

    // Download model if not already downloaded
    await downloadModel(onProgress: onProgress);

    // Initialize model for inference
    onProgress(0.95, 'Initializing inference engine...');
    await initializeModel();

    onProgress(1.0, 'Model ready');
  }

  /// Generate text with streaming via callback
  Future<void> generate({
    required String prompt,
    required void Function(String token) onToken,
    int maxTokens = defaultMaxTokens,
  }) async {
    if (!_isInitialized) {
      throw ModelServiceException('Model not initialized. Call initialize first.');
    }

    // Use simple completion for prompt-based generation
    final messages = [
      ChatMessage(content: prompt, role: 'user'),
    ];

    final streamedResult = await _lm!.generateCompletionStream(
      messages: messages,
      params: CactusCompletionParams(maxTokens: maxTokens),
    );

    await for (final token in streamedResult.stream) {
      onToken(token);
    }
  }

  /// Get device info - returns basic info about the model/device
  Future<Map<String, String>> getDeviceInfo() async {
    // CactusLM doesn't expose a public getDeviceInfo API
    // Return what we know from our configuration
    return {
      'device': 'Mobile (on-device inference)',
      'model': modelSlug,
      'status': _isInitialized ? 'Ready' : 'Not initialized',
    };
  }

  /// Generate a raw completion with an optional custom system prompt.
  ///
  /// Used by the benchmark HTTP server so evaluation harnesses can supply
  /// their own system prompt (e.g. "Answer with only A/B/C/D").
  Future<String> generateRaw({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 512,
  }) async {
    if (!_isInitialized) {
      throw ModelServiceException('Model not initialized. Call initializeModel first.');
    }

    final messages = [
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        ChatMessage(content: systemPrompt, role: 'system'),
      ChatMessage(content: prompt, role: 'user'),
    ];

    final result = await _lm!.generateCompletion(
      messages: messages,
      params: CactusCompletionParams(maxTokens: maxTokens),
    );

    if (!result.success) {
      throw ModelServiceException('Generation failed: ${result.response}');
    }

    return _cleanResponse(result.response);
  }

  /// Unload the model and free resources
  void dispose() {
    _lm?.unload();
    _lm = null;
    _isInitialized = false;
    _downloadProgress = 0.0;
    _downloadStatus = '';
  }
}

/// Result from a completion request
class CompletionResult {
  final String response;
  final double tokensPerSecond;

  CompletionResult({
    required this.response,
    required this.tokensPerSecond,
  });
}

/// Result from a completion request with tool calling support
class CompletionResultWithTools {
  final String response;
  final double tokensPerSecond;
  final List<ToolCall> toolCalls;

  CompletionResultWithTools({
    required this.response,
    required this.tokensPerSecond,
    required this.toolCalls,
  });

  /// Whether the model requested any tool calls
  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Exception thrown by ModelService
class ModelServiceException implements Exception {
  final String message;

  ModelServiceException(this.message);

  @override
  String toString() => 'ModelServiceException: $message';
}
