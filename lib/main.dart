import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String OPENROUTER_API_KEY = "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";
const String OPENROUTER_MODEL = "deepseek/deepseek-chat";
const String SYSTEM_PROMPT = "You are a helpful AI assistant. You must reply ONLY in Bengali. Use simple, natural Bengali.";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDark') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', isDark);
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'চ্যাটবাংলা+',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A1B9A),
          primary: const Color(0xFF6A1B9A),
          secondary: const Color(0xFFAB47BC),
        ),
        textTheme: GoogleFonts.notoSansTextTheme(),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9C27B0),
          brightness: Brightness.dark,
          primary: const Color(0xFFBA68C8),
          secondary: const Color(0xFFCE93D8),
        ),
        textTheme: GoogleFonts.notoSansTextTheme(ThemeData.dark().textTheme),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: Home(onThemeChanged: _toggleTheme, isDark: _themeMode == ThemeMode.dark),
    );
  }
}

class Home extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDark;
  const Home({super.key, required this.onThemeChanged, required this.isDark});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const ChatScreen(),
      PdfQaScreen(),
      const TtsScreen(),
      SettingsScreen(onThemeChanged: widget.onThemeChanged, isDark: widget.isDark),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final labels = ['চ্যাট', 'PDF', 'কথন', 'সেটিংস'];
    final icons = [Icons.chat_bubble_rounded, Icons.picture_as_pdf_rounded, Icons.volume_up_rounded, Icons.settings_rounded];

    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        height: 70,
        elevation: 8,
        destinations: List.generate(
          4,
              (i) => NavigationDestination(
            icon: Icon(icons[i]),
            selectedIcon: Icon(icons[i], size: 28),
            label: labels[i],
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scroll = ScrollController();

  bool _loading = false;
  bool _typing = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tts.stop();
    _scroll.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;

    setState(() {
      _messages.add({'from': 'user', 'text': trimmed});
      _loading = true;
      _typing = true;
    });
    _ctrl.clear();
    _scrollToEnd();
    _animationController.forward();

    String? reply;
    try {
      reply = await _callGemini(trimmed);
      if (reply != null && reply.isNotEmpty) {
        setState(() {
          _messages.add({'from': 'bot', 'text': reply});
        });
        _scrollToEnd();
        await _tts.setLanguage('bn-BD');
        await _tts.speak(reply);
      } else {
        setState(() {
          _messages.add({'from': 'bot', 'text': 'দুঃখিত, আমি এখন উত্তর দিতে পারছি না। আবার চেষ্টা করুন।'});
        });
        _scrollToEnd();
      }
    } catch (e, st) {
      debugPrint('Gemini call error: $e\n$st');
      setState(() {
        _messages.add({'from': 'bot', 'text': 'দুঃখিত, সংযোগে সমস্যা হয়েছে। আবার চেষ্টা করুন।'});
      });
      _scrollToEnd();
    } finally {
      setState(() {
        _loading = false;
        _typing = false;
      });
      _animationController.reverse();
    }
  }

  Future<String?> _callGemini(String text) async {
    // Use OpenRouter API with deepseek/deepseek-chat model
    final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

    try {
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $OPENROUTER_API_KEY',
        },
        body: jsonEncode({
          'model': OPENROUTER_MODEL,
          'messages': [
            {'role': 'system', 'content': SYSTEM_PROMPT},
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.7,
          'max_tokens': 1024,
        }),
      ).timeout(const Duration(seconds: 30));

      debugPrint('========== OPENROUTER API DEBUG ==========');
      debugPrint('Status Code: ${resp.statusCode}');
      debugPrint('Response Body: ${resp.body}');
      debugPrint('==========================================');

      if (resp.statusCode != 200) {
        debugPrint('API Error ${resp.statusCode}: ${resp.body}');
        final apiMessage = _extractApiErrorMessage(resp.body);
        if (resp.statusCode == 400) {
          _showSnack('রিকুয়েস্টে সমস্যা হয়েছে (400)। বিস্তারিত: $apiMessage');
        } else if (resp.statusCode == 401 || resp.statusCode == 403) {
          _showSnack('API Key সঠিক নয় বা অনুমতি নেই (${resp.statusCode})। OpenRouter থেকে Key যাচাই করুন।');
        } else if (resp.statusCode == 404) {
          _showSnack('ব্যবহৃত মডেল বা এন্ডপয়েন্ট পাওয়া যায়নি (404)। অ্যাপ বা মডেল কনফিগারেশন আপডেট করুন।');
        } else if (resp.statusCode == 429) {
          _showSnack('API Limit অতিক্রম হয়েছে। একটু পরে চেষ্টা করুন।');
        } else if (resp.statusCode >= 500) {
          _showSnack('সার্ভার-পক্ষের ত্রুটি (${resp.statusCode})। কিছুক্ষণ পরে আবার চেষ্টা করুন।');
        } else {
          _showSnack('API ত্রুটি (${resp.statusCode}): $apiMessage');
        }
        return null;
      }

      final j = jsonDecode(resp.body);
      debugPrint('Parsed JSON: $j');

      if (j is Map && j.containsKey('choices')) {
        final choices = j['choices'] as List;
        debugPrint('Choices count: ${choices.length}');

        if (choices.isNotEmpty) {
          final choice = choices[0];
          debugPrint('First choice: $choice');

          if (choice['message'] != null && choice['message']['content'] != null) {
            final text = choice['message']['content'].toString().trim();
            debugPrint('Extracted text: $text');
            return text;
          } else {
            debugPrint('No content in message');
          }
        } else {
          debugPrint('Choices array is empty');
        }
      } else {
        debugPrint('No choices key in response');
      }

      return null;
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('Timeout in _callGemini: $e');
      debugPrint('Stack trace: $stackTrace');
      _showSnack('সার্ভারের উত্তর পেতে দেরি হচ্ছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।');
      return null;
    } on SocketException catch (e, stackTrace) {
      debugPrint('Network error in _callGemini: $e');
      debugPrint('Stack trace: $stackTrace');
      _showSnack('ইন্টারনেট সংযোগ যাচাই করুন এবং আবার চেষ্টা করুন।');
      return null;
    } catch (e, stackTrace) {
      debugPrint('Unexpected exception in _callGemini: $e');
      debugPrint('Stack trace: $stackTrace');
      _showSnack('অপ্রত্যাশিত ত্রুটি ঘটেছে: $e');
      return null;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    }
  }

  String _extractApiErrorMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map && (j['error'] as Map)['message'] is String) {
        return (j['error'] as Map)['message'] as String;
      }
    } catch (_) {
      // ignore JSON parse errors
    }
    return 'অজানা ত্রুটি'; // unknown error
  }

  Widget _bubble(Map<String, dynamic> m, int index) {
    final isUser = m['from'] == 'user';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            gradient: isUser
                ? LinearGradient(
              colors: isDark
                  ? [const Color(0xFFBA68C8), const Color(0xFF9C27B0)]
                  : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
                : null,
            color: isUser ? null : (isDark ? Colors.grey[800] : Colors.grey[200]),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isUser ? 20 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '${m['text']}',
            style: TextStyle(
              color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
              fontSize: 16,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.smart_toy_rounded, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('চ্যাটবট — বাংলা', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)]
                  : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _messages.clear());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('চ্যাট পরিষ্কার করা হয়েছে'), duration: Duration(seconds: 1)),
              );
            },
            tooltip: 'চ্যাট পরিষ্কার করুন',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1A1A1A), const Color(0xFF2D2D2D)]
                : [const Color(0xFFF8F0FC), const Color(0xFFEDE7F6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 80,
                      color: theme.colorScheme.primary.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'নমস্কার! আমি আপনার সহায়ক',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onBackground.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'আপনার প্রশ্ন জিজ্ঞাসা করুন...',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onBackground.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _bubble(_messages[i], i),
              ),
            ),
            if (_typing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTypingDot(0),
                          const SizedBox(width: 4),
                          _buildTypingDot(1),
                          const SizedBox(width: 4),
                          _buildTypingDot(2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _ctrl,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(_ctrl.text),
                          enabled: !_loading,
                          decoration: InputDecoration(
                            hintText: 'আপনার প্রশ্ন লিখুন...',
                            hintStyle: TextStyle(
                              color: theme.colorScheme.onBackground.withOpacity(0.4),
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFFBA68C8), const Color(0xFF9C27B0)]
                              : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _loading ? null : () => _send(_ctrl.text),
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 56,
                            height: 56,
                            alignment: Alignment.center,
                            child: _loading
                                ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        final offset = (value + (index * 0.33)) % 1.0;
        final scale = 0.5 + (0.5 * (1 - (offset - 0.5).abs() * 2));
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
      onEnd: () {
        if (_typing) {
          setState(() {});
        }
      },
    );
  }
}

class PdfQaScreen extends StatefulWidget {
  PdfQaScreen({super.key});
  @override
  State<PdfQaScreen> createState() => _PdfQaScreenState();
}

class _PdfQaScreenState extends State<PdfQaScreen> {
  File? _pdfFile;
  final TextEditingController _excerptCtrl = TextEditingController();
  final TextEditingController _questionCtrl = TextEditingController();
  final List<Map<String, dynamic>> _qaHistory = [];
  bool _loading = false;

  @override
  void dispose() {
    _excerptCtrl.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (res == null || res.files.isEmpty) return;
      final path = res.files.first.path;
      if (path != null) {
        setState(() {
          _pdfFile = File(path);
          _qaHistory.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF সফলভাবে লোড হয়েছে'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('PDF pick error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF নির্বাচনে সমস্যা হয়েছে')),
      );
    }
  }

  Future<void> _ask() async {
    final excerpt = _excerptCtrl.text.trim();
    final question = _questionCtrl.text.trim();

    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('প্রশ্ন লিখুন।')),
      );
      return;
    }

    setState(() => _loading = true);

    final prompt = excerpt.isEmpty
        ? "Answer this question in Bengali:\n$question"
        : "Based on this PDF excerpt:\n$excerpt\n\nQuestion: $question\n\nAnswer in Bengali concisely:";

    try {
      final reply = await _callGemini(prompt);
      setState(() {
        _loading = false;
        if (reply != null && reply.isNotEmpty) {
          _qaHistory.insert(0, {
            'question': question,
            'answer': reply,
            'timestamp': DateTime.now(),
          });
        }
      });

      if (reply != null && reply.isNotEmpty) {
        _questionCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('উত্তর পাওয়া গেছে'), duration: Duration(seconds: 1)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('উত্তর পাওয়া যায়নি। আবার চেষ্টা করুন।')),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('PDF ask error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সংযোগে সমস্যা হয়েছে।')),
      );
    }
  }

  Future<String?> _callGemini(String prompt) async {
    // Use OpenRouter API with deepseek/deepseek-chat model
    final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

    try {
      final resp = await http
          .post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $OPENROUTER_API_KEY',
        },
        body: jsonEncode({
          'model': OPENROUTER_MODEL,
          'messages': [
            {'role': 'system', 'content': SYSTEM_PROMPT},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': 1024,
        }),
      )
          .timeout(const Duration(seconds: 30));

      debugPrint('PDF->OpenRouter status=${resp.statusCode}');
      debugPrint('PDF->OpenRouter body=${resp.body}');

      if (resp.statusCode != 200) {
        final apiMessage = _extractPdfApiErrorMessage(resp.body);
        debugPrint('PDF OpenRouter error: ${resp.statusCode} $apiMessage');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF API তে সমস্যা (${resp.statusCode}): $apiMessage'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return null;
      }

      try {
        final j = jsonDecode(resp.body);
        if (j is Map && j.containsKey('choices')) {
          final choices = j['choices'] as List;
          if (choices.isNotEmpty) {
            final choice = choices[0];
            if (choice['message'] != null && choice['message']['content'] != null) {
              return choice['message']['content'].toString().trim();
            }
          }
        }
        return null;
      } catch (e) {
        debugPrint('PDF parse error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF থেকে প্রাপ্ত ডেটা বোঝা যায়নি। আবার চেষ্টা করুন।'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return null;
      }
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('PDF Timeout in _callGemini: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF উত্তর পেতে দেরি হচ্ছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return null;
    } on SocketException catch (e, stackTrace) {
      debugPrint('PDF Network error in _callGemini: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ইন্টারনেট সংযোগ যাচাই করুন এবং আবার চেষ্টা করুন।'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint('PDF Unexpected exception in _callGemini: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF API তে অপ্রত্যাশিত ত্রুটি ঘটেছে।'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  String _extractPdfApiErrorMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map && (j['error'] as Map)['message'] is String) {
        return (j['error'] as Map)['message'] as String;
      }
    } catch (_) {
      // ignore JSON parse errors
    }
    return 'অজানা ত্রুটি';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF প্রশ্ন-উত্তর', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)]
                  : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
            ),
          ),
        ),
        actions: [
          if (_pdfFile != null)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                setState(() {
                  _pdfFile = null;
                  _qaHistory.clear();
                  _excerptCtrl.clear();
                  _questionCtrl.clear();
                });
              },
              tooltip: 'PDF বন্ধ করুন',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _pdfFile != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                          color: _pdfFile != null ? Colors.green : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _pdfFile != null
                                ? _pdfFile!.path.split(Platform.pathSeparator).last
                                : 'কোনো PDF নির্বাচিত নেই',
                            style: TextStyle(
                              fontWeight: _pdfFile != null ? FontWeight.w500 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('নির্বাচন'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _pdfFile != null
                ? SfPdfViewer.file(
              _pdfFile!,
              pageLayoutMode: PdfPageLayoutMode.single,
            )
                : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 80,
                    color: theme.colorScheme.primary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'PDF আপলোড করুন',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onBackground.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ডকুমেন্ট নির্বাচন করুন এবং প্রশ্ন করুন',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onBackground.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_qaHistory.isNotEmpty) ...[
                  const Text(
                    'সাম্প্রতিক উত্তর:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: ListView.builder(
                      itemCount: _qaHistory.length,
                      itemBuilder: (context, index) {
                        final qa = _qaHistory[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'প্রশ্ন: ${qa['question']}',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'উত্তর: ${qa['answer']}',
                                style: TextStyle(
                                  color: theme.colorScheme.onBackground.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _excerptCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'PDF থেকে টেক্সট (ঐচ্ছিক)',
                    hintText: 'PDF থেকে প্রাসঙ্গিক অংশ পেস্ট করুন...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.grey[800] : Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questionCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _ask(),
                        decoration: InputDecoration(
                          hintText: 'আপনার প্রশ্ন লিখুন...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.white,
                          prefixIcon: const Icon(Icons.question_answer_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFFBA68C8), const Color(0xFF9C27B0)]
                              : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _loading ? null : _ask,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        child: _loading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Text('জিজ্ঞাসা করুন', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});
  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _ctrl = TextEditingController();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
  }

  Future<void> _speak() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('টেক্সট লিখুন')),
      );
      return;
    }
    setState(() => _isSpeaking = true);
    await _tts.setLanguage('bn-BD');
    await _tts.speak(text);
  }

  Future<void> _stop() async {
    await _tts.stop();
    setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    _tts.stop();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('টেক্সট টু স্পিচ', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)]
                  : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1A1A1A), const Color(0xFF2D2D2D)]
                : [const Color(0xFFF8F0FC), const Color(0xFFEDE7F6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.volume_up_rounded,
                size: 80,
                color: theme.colorScheme.primary.withOpacity(0.7),
              ),
              const SizedBox(height: 24),
              Text(
                'বাংলা টেক্সট লিখুন এবং শুনুন',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onBackground.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'এখানে বাংলা টেক্সট লিখুন...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[800] : Colors.white,
                  contentPadding: const EdgeInsets.all(20),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFFBA68C8), const Color(0xFF9C27B0)]
                              : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isSpeaking ? null : _speak,
                        icon: Icon(_isSpeaking ? Icons.stop_rounded : Icons.play_arrow_rounded),
                        label: Text(_isSpeaking ? 'বাজছে...' : 'শোনান'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  if (_isSpeaking) ...[
                    const SizedBox(width: 12),
                    Container(
                      height: 56,
                      width: 56,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _stop,
                        icon: const Icon(Icons.stop, color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDark;
  const SettingsScreen({super.key, required this.onThemeChanged, required this.isDark});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('সেটিংস', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)]
                  : [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1A1A1A), const Color(0xFF2D2D2D)]
                : [const Color(0xFFF8F0FC), const Color(0xFFEDE7F6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('ডার্ক মোড', style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: const Text('থিম পরিবর্তন করুন'),
                    value: widget.isDark,
                    onChanged: widget.onThemeChanged,
                    secondary: Icon(
                      widget.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.info_rounded,
                            color: theme.colorScheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'অ্যাপ সম্পর্কে',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildInfoRow(Icons.app_settings_alt_rounded, 'সংস্করণ', 'ChatBangla+ v2.0'),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.code_rounded, 'প্রযুক্তি', 'Built with Flutter'),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.smart_toy_rounded, 'AI মডেল', 'Powered by Gemini AI'),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.language_rounded, 'ভাষা', 'বাংলা ভাষা সহায়তা'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.star_rounded, color: Colors.amber[700], size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'বৈশিষ্ট্য',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildFeature(Icons.chat_bubble_rounded, 'বাংলা চ্যাটবট'),
                    const SizedBox(height: 8),
                    _buildFeature(Icons.picture_as_pdf_rounded, 'PDF বিশ্লেষণ'),
                    const SizedBox(height: 8),
                    _buildFeature(Icons.volume_up_rounded, 'টেক্সট টু স্পিচ'),
                    const SizedBox(height: 8),
                    _buildFeature(Icons.dark_mode_rounded, 'ডার্ক/লাইট থিম'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontSize: 15)),
      ],
    );
  }
}
