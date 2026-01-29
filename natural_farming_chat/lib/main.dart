import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/model_service.dart';
import 'services/rag_service.dart';
import 'services/calculator_service.dart';

void main() {
  runApp(const NaturalFarmingChatApp());
}

class NaturalFarmingChatApp extends StatelessWidget {
  const NaturalFarmingChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Natural Farming Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

/// Represents a chat message
class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
        'content': content,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Create from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        content: json['content'] as String,
        isUser: json['isUser'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Main chat screen
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  final ModelService _modelService = ModelService();
  final RagService _ragService = RagService();
  final CalculatorService _calculatorService = CalculatorService();

  bool _isLoading = false;
  bool _isInitialized = false;
  bool _agenticMode = false;
  String _initStatus = 'Starting...';
  double _initProgress = 0.0;
  String? _deviceInfo;

  // Persistence keys
  static const String _chatHistoryKey = 'chat_history';
  static const String _agenticModeKey = 'agentic_mode';

  @override
  void initState() {
    super.initState();
    _loadPersistedSettings();
    _initializeServices();
  }

  /// Load persisted settings from SharedPreferences
  Future<void> _loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load agentic mode setting
    final savedAgenticMode = prefs.getBool(_agenticModeKey);
    if (savedAgenticMode != null) {
      setState(() {
        _agenticMode = savedAgenticMode;
      });
    }

    // Load chat history
    final savedHistory = prefs.getString(_chatHistoryKey);
    if (savedHistory != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(savedHistory);
        final loadedMessages = jsonList
            .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
            .toList();
        if (loadedMessages.isNotEmpty) {
          setState(() {
            _messages.clear();
            _messages.addAll(loadedMessages);
          });
        }
      } catch (e) {
        // Ignore invalid saved data
      }
    }
  }

  /// Save chat history to SharedPreferences
  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _messages.map((m) => m.toJson()).toList();
    await prefs.setString(_chatHistoryKey, jsonEncode(jsonList));
  }

  /// Save agentic mode setting
  Future<void> _saveAgenticMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_agenticModeKey, _agenticMode);
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize the model
      await _modelService.initialize(
        onProgress: (progress, status) {
          setState(() {
            _initProgress = progress * 0.7; // Model is 70% of init
            _initStatus = status;
          });
        },
      );

      // Get device info
      final deviceInfo = await _modelService.getDeviceInfo();
      _deviceInfo = deviceInfo['device'] ?? 'Unknown';

      // Initialize RAG with the model
      await _ragService.initialize(_modelService.lm!);

      setState(() {
        _initProgress = 0.8;
        _initStatus = 'Loading knowledge base...';
      });

      // Load knowledge base
      await _ragService.loadKnowledgeBase(
        onProgress: (progress, status) {
          setState(() {
            _initProgress = 0.8 + (progress * 0.2); // Knowledge is 20% of init
            _initStatus = status;
          });
        },
      );

      setState(() {
        _isInitialized = true;
        // Only add welcome message if no history was loaded
        if (_messages.isEmpty) {
          _messages.add(ChatMessage(
            content: 'Hello! I\'m your Natural Farming assistant. '
                'Ask me anything about organic farming, composting, '
                'fermented plant juice, or nutrient requirements for plants.',
            isUser: false,
          ));
        }
      });
    } catch (e) {
      setState(() {
        _initStatus = 'Error: $e';
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    final userMessage = ChatMessage(content: text.trim(), isUser: true);
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      // Get relevant context from RAG
      final context = await _ragService.searchContext(text);

      // Build prompt with context
      final prompt = _buildPrompt(text, context);

      // Generate response
      String response = '';
      await _modelService.generate(
        prompt: prompt,
        onToken: (token) {
          response += token;
        },
      );

      // Clean the response
      response = _cleanResponse(response);

      // Process calculator tags if in agentic mode
      if (_agenticMode) {
        response = _calculatorService.processResponse(response);
      }

      setState(() {
        _messages.add(ChatMessage(content: response, isUser: false));
        _isLoading = false;
      });
      _saveChatHistory();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          content: 'Sorry, I encountered an error: $e',
          isUser: false,
        ));
        _isLoading = false;
      });
      _saveChatHistory();
    }

    _scrollToBottom();
  }

  String _buildPrompt(String question, String context) {
    final systemPrompt = '''You are a helpful natural farming assistant.
Provide accurate, practical advice about organic farming, composting,
fermented plant extracts (FPE/FPJ), Korean Natural Farming (KNF), and plant nutrition.
Keep responses concise and actionable.''';

    String prompt = systemPrompt;

    if (context.isNotEmpty) {
      prompt += '\n\nRelevant knowledge:\n$context';
    }

    if (_agenticMode) {
      prompt += '\n\nYou have access to a calculator. Use <calculate>expression</calculate> for math.';
    }

    prompt += '\n\nUser question: $question\n\nAssistant:';

    return prompt;
  }

  String _cleanResponse(String response) {
    // Remove common artifacts from model output
    var cleaned = response;

    // Remove thinking tags
    cleaned = cleaned.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');

    // Remove prompt structure markers
    cleaned = cleaned.replaceAll(RegExp(r'\[/?CONTEXT\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[/?QUESTION\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[/?ANSWER\]'), '');

    // Remove leading/trailing whitespace and normalize newlines
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearHistory() {
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(
        content: 'Chat cleared. How can I help you?',
        isUser: false,
      ));
    });
    _saveChatHistory();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _modelService.dispose();
    // RagService.dispose() is async but we can't await in synchronous dispose
    // The service will clean up eventually when the future completes
    _ragService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Natural Farming Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _buildMessageList(),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.eco,
                size: 80,
                color: Colors.green,
              ),
              const SizedBox(height: 24),
              const Text(
                'Natural Farming Chat',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              LinearProgressIndicator(value: _initProgress),
              const SizedBox(height: 16),
              Text(
                _initStatus,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.eco, size: 48, color: Colors.green),
                SizedBox(height: 8),
                Text(
                  'Natural Farming AI',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '100% Local • Privacy First',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Device'),
            subtitle: Text(_deviceInfo ?? 'Unknown'),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.psychology),
            title: const Text('Agentic Mode'),
            subtitle: const Text('Calculator tools enabled'),
            value: _agenticMode,
            onChanged: (value) {
              setState(() {
                _agenticMode = value;
              });
              _saveAgenticMode();
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear Chat History'),
            onTap: () {
              _clearHistory();
              Navigator.pop(context);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Democratizing access to farming knowledge',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return const _TypingIndicator();
        }
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Ask about natural farming...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                enabled: !_isLoading,
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isLoading
                  ? null
                  : () => _sendMessage(_textController.text),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat message bubble widget
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(
            color: isUser
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Typing indicator shown while waiting for response
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Thinking...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
