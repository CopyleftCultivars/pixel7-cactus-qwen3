import 'package:cactus/cactus.dart' show ToolCall;

import 'calculator_service.dart';
import 'rag_service.dart';

/// Service for executing tool calls requested by the LLM.
/// Dispatches tool calls to appropriate handlers (RAG lookups, calculations).
class ToolExecutor {
  final RagService _ragService;
  final CalculatorService _calculatorService;

  ToolExecutor({
    required RagService ragService,
    required CalculatorService calculatorService,
  })  : _ragService = ragService,
        _calculatorService = calculatorService;

  /// Execute a tool call and return the result
  Future<ToolResult> execute(ToolCall toolCall) async {
    print('[TOOL_DEBUG] Executing tool: ${toolCall.name}');
    print('[TOOL_DEBUG] Arguments: ${toolCall.arguments}');

    ToolResult result;
    switch (toolCall.name) {
      case 'npk_lookup':
        result = await _executeNPKLookup(toolCall.arguments);
        break;
      case 'calculate':
        result = await _executeCalculation(toolCall.arguments);
        break;
      default:
        result = ToolResult(
          toolName: toolCall.name,
          success: false,
          result: 'Unknown tool: ${toolCall.name}',
        );
    }

    print('[TOOL_DEBUG] Tool result - success: ${result.success}');
    print('[TOOL_DEBUG] Tool result - output: ${result.result.substring(0, result.result.length.clamp(0, 200))}...');
    return result;
  }

  /// Execute multiple tool calls and return all results
  Future<List<ToolResult>> executeAll(List<ToolCall> toolCalls) async {
    final results = <ToolResult>[];
    for (final call in toolCalls) {
      results.add(await execute(call));
    }
    return results;
  }

  /// Execute NPK lookup using RAG service
  Future<ToolResult> _executeNPKLookup(Map<String, String> arguments) async {
    final plant = arguments['plant'];
    if (plant == null || plant.isEmpty) {
      return ToolResult(
        toolName: 'npk_lookup',
        success: false,
        result: 'Missing required parameter: plant',
      );
    }

    final queryType = arguments['query_type'] ?? 'npk_ratio';

    // Build targeted RAG query based on query type
    final query = _buildNPKQuery(plant, queryType);

    try {
      final context = await _ragService.searchContext(query);

      if (context.isEmpty) {
        return ToolResult(
          toolName: 'npk_lookup',
          success: true,
          result: 'No specific information found for $plant $queryType. '
              'Try general organic gardening practices.',
          metadata: {'plant': plant, 'query_type': queryType},
        );
      }

      return ToolResult(
        toolName: 'npk_lookup',
        success: true,
        result: context,
        metadata: {'plant': plant, 'query_type': queryType},
      );
    } catch (e) {
      return ToolResult(
        toolName: 'npk_lookup',
        success: false,
        result: 'Error searching knowledge base: $e',
      );
    }
  }

  /// Build a targeted RAG query for NPK lookup
  String _buildNPKQuery(String plant, String queryType) {
    switch (queryType) {
      case 'npk_ratio':
        return '$plant NPK ratio nitrogen phosphorus potassium requirements';
      case 'fertilizer_schedule':
        return '$plant fertilizer feeding schedule timing application';
      case 'organic_sources':
        return '$plant organic fertilizer natural nutrient sources compost';
      case 'deficiency_symptoms':
        return '$plant nutrient deficiency symptoms yellowing wilting signs';
      default:
        return '$plant NPK nutrients fertilizer requirements';
    }
  }

  /// Execute calculation using calculator service
  Future<ToolResult> _executeCalculation(Map<String, String> arguments) async {
    final expression = arguments['expression'];
    if (expression == null || expression.isEmpty) {
      return ToolResult(
        toolName: 'calculate',
        success: false,
        result: 'Missing required parameter: expression',
      );
    }

    final context = arguments['context'];
    final calcResult = _calculatorService.evaluate(expression);
    final isError = calcResult.startsWith('Error:');

    return ToolResult(
      toolName: 'calculate',
      success: !isError,
      result: isError ? calcResult : calcResult,
      metadata: {
        'expression': expression,
        if (context != null) 'context': context,
      },
    );
  }

  /// Format tool results for inclusion in follow-up prompt
  String formatResultsForPrompt(List<ToolResult> results) {
    if (results.isEmpty) return '';

    final buffer = StringBuffer('Tool Results:\n');

    for (final result in results) {
      buffer.writeln('--- ${result.toolName} ---');
      if (result.success) {
        buffer.writeln(result.result);
      } else {
        buffer.writeln('Error: ${result.result}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}

/// Result from executing a tool
class ToolResult {
  final String toolName;
  final bool success;
  final String result;
  final Map<String, String>? metadata;

  ToolResult({
    required this.toolName,
    required this.success,
    required this.result,
    this.metadata,
  });

  @override
  String toString() => 'ToolResult($toolName: ${success ? "OK" : "FAIL"} - $result)';
}
