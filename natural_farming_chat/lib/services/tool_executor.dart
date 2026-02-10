import 'package:cactus/cactus.dart' show ToolCall;

import 'calculator_service.dart';
import 'plant_lookup_service.dart';

/// Service for executing tool calls requested by the LLM.
/// Dispatches tool calls to appropriate handlers (plant lookups, calculations).
class ToolExecutor {
  final PlantLookupService _plantLookupService;
  final CalculatorService _calculatorService;

  ToolExecutor({
    required PlantLookupService plantLookupService,
    required CalculatorService calculatorService,
  })  : _plantLookupService = plantLookupService,
        _calculatorService = calculatorService;

  /// Execute a tool call and return the result
  Future<ToolResult> execute(ToolCall toolCall) async {
    print('[TOOL_DEBUG] Executing tool: ${toolCall.name}');
    print('[TOOL_DEBUG] Arguments: ${toolCall.arguments}');

    ToolResult result;
    switch (toolCall.name) {
      case 'npk_lookup':
        result = _executeNPKLookup(toolCall.arguments);
        break;
      case 'calculate':
        result = _executeCalculation(toolCall.arguments);
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

  /// Execute NPK/mineral lookup using direct JSON plant database
  ToolResult _executeNPKLookup(Map<String, String> arguments) {
    final plant = arguments['plant'];
    if (plant == null || plant.isEmpty) {
      return ToolResult(
        toolName: 'npk_lookup',
        success: false,
        result: 'Missing required parameter: plant',
      );
    }

    final lookupResult = _plantLookupService.lookup(plant);

    return ToolResult(
      toolName: 'npk_lookup',
      success: lookupResult.found,
      result: lookupResult.message,
      metadata: {
        'plant': plant,
        if (lookupResult.plantName != null) 'matched': lookupResult.plantName!,
      },
    );
  }

  /// Execute calculation using calculator service
  ToolResult _executeCalculation(Map<String, String> arguments) {
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
      result: calcResult,
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
