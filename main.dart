import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RonghorAIApp());
}

const brandPurple = Color(0xFF8B5CF6);
const brandBlue = Color(0xFF38BDF8);

class RonghorAIApp extends StatelessWidget {
  const RonghorAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ronghor AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF121A2B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1020),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  ChatMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      ChatMessage(json['role'] as String, json['content'] as String);
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _tts = FlutterTts();
  final _speech = stt.SpeechToText();
  final List<ChatMessage> _messages = [];
  String _baseUrl = 'http://10.0.2.2:8000';
  bool _busy = false;
  bool _webSearch = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndHistory();
    _tts.setLanguage('en-IN');
  }

  Future<void> _loadSettingsAndHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('backend_url');
    final saved = prefs.getString('chat_history');
    if (!mounted) return;
    setState(() {
      if (url != null && url.trim().isNotEmpty) _baseUrl = url.trim();
      if (saved != null) {
        try {
          final decoded = jsonDecode(saved) as List<dynamic>;
          _messages.addAll(decoded.map((e) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))));
        } catch (_) {
          // Ignore an invalid old history and start with an empty conversation.
        }
      }
      if (_messages.isEmpty) {
        _messages.add(ChatMessage(
          'assistant',
          'Hello! I’m Ronghor AI. Ask me anything, or open Settings to connect your AI backend.',
        ));
      }
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'chat_history',
      jsonEncode(_messages.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _error = null;
      _messages.add(ChatMessage('user', text));
      _busy = true;
    });
    await _saveHistory();
    _jumpToBottom();

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': text,
              'web_search': _webSearch,
              'history': _messages
                  .take(_messages.length - 1)
                  .where((m) => m.role == 'user' || m.role == 'assistant')
                  .toList()
                  .reversed
                  .take(12)
                  .toList()
                  .reversed
                  .map((m) => m.toJson())
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server returned ${response.statusCode}: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = (data['answer'] ?? 'The AI returned an empty response.')
          .toString();
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage('assistant', answer)));
      await _saveHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the AI backend. Check the backend URL, server, and API key in Settings.';
        _messages.add(ChatMessage(
          'assistant',
          'I couldn’t connect to the AI service. Open Settings to verify the backend URL. Details: $e',
        ));
      });
      await _saveHistory();
    } finally {
      if (mounted) setState(() => _busy = false);
      _jumpToBottom();
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition is unavailable on this device.')),
        );
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _controller.text = result.recognizedWords;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _openSettings() async {
    final urlController = TextEditingController(text: _baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ronghor AI settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backend URL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://your-server.example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use your deployed HTTPS backend URL. 10.0.2.2 only works for the Android emulator, not your physical phone.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, urlController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', result.replaceAll(RegExp(r'/$'), ''));
    if (!mounted) return;
    setState(() => _baseUrl = result.replaceAll(RegExp(r'/$'), ''));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backend URL saved')),
    );
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text('This removes the locally saved chat history on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _messages
        ..clear()
        ..add(ChatMessage('assistant', 'New conversation started. What would you like to explore?'));
      _error = null;
    });
    await _saveHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 54,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(colors: [brandPurple, brandBlue]),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ronghor AI', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
            Text('Your AI companion', style: TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            onPressed: _clearChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF121A2B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, size: 19, color: brandBlue),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Web search', style: TextStyle(fontWeight: FontWeight.w600))),
                  Switch(
                    value: _webSearch,
                    onChanged: (value) => setState(() => _webSearch = value),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_busy && index == _messages.length) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text('Ronghor AI is thinking…', style: TextStyle(color: Colors.white70)),
                        ]),
                      ),
                    );
                  }
                  final message = _messages[index];
                  final isUser = message.role == 'user';
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.fromLTRB(14, 11, 10, 8),
                      decoration: BoxDecoration(
                        gradient: isUser
                            ? const LinearGradient(colors: [Color(0xFF6D4AFF), Color(0xFF4C6FFF)])
                            : null,
                        color: isUser ? null : const Color(0xFF172238),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isUser ? 18 : 5),
                          bottomRight: Radius.circular(isUser ? 5 : 18),
                        ),
                        border: isUser ? null : Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(message.content, style: const TextStyle(fontSize: 15, height: 1.45)),
                          if (!isUser)
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Read aloud',
                                onPressed: () => _speak(message.content),
                                icon: const Icon(Icons.volume_up_outlined, size: 18, color: Colors.white60),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0B1020),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _listening ? 'Stop listening' : 'Voice input',
                    onPressed: _toggleVoiceInput,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded,
                        color: _listening ? Colors.redAccent : brandBlue),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'Message Ronghor AI…',
                        filled: true,
                        fillColor: const Color(0xFF172238),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [brandPurple, brandBlue]),
                    ),
                    child: IconButton(
                      onPressed: _busy ? null : _send,
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
