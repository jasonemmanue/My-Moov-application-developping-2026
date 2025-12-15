import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  XFile? _selectedImage;
  String? _imageUrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _messages.add({
      'text': '👋 Salut ! Je suis ton assistant. Tu peux m\'envoyer du texte et des images !',
      'isBot': true,
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImage == null && (_imageUrl == null || _imageUrl!.isEmpty)) {
      return;
    }

    setState(() {
      _messages.add({
        'text': text,
        'isBot': false,
        'image': _selectedImage?.path ?? _imageUrl,
      });
      _controller.clear();
      _isTyping = true;
      _selectedImage = null;
      _imageUrl = null;
    });
    _scrollToBottom();

    final payload = <String, dynamic>{'message': text};

    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      payload['image_base64'] = base64Encode(bytes);
    } else if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      payload['image_url'] = _imageUrl;
    }

    try {
      final request = http.Request(
        'POST',
        Uri.parse('http://192.168.42.203:8000/api/chat/stream/'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(payload);

      final streamedResponse = await request.send();
      if (streamedResponse.statusCode != 200) {
        _addBotMessage('❌ Erreur serveur');
        return;
      }

      String accumulatedText = '';
      await for (var chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data);
            if (json['text'] != null) {
              accumulatedText += json['text'];
              if (_messages.last['isBot'] == true) {
                setState(() {
                  _messages.last['text'] = accumulatedText;
                });
              } else {
                setState(() {
                  _messages.add({'text': accumulatedText, 'isBot': true});
                });
              }
              _scrollToBottom();
            }
          } catch (e) {
            // Ignore
          }
        }
      }
    } catch (e) {
      _addBotMessage('❌ Erreur réseau : $e');
    } finally {
      setState(() {
        _isTyping = false;
      });
    }
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add({'text': text, 'isBot': true});
      _isTyping = false;
    });
    _scrollToBottom();
  }

  void _newConversation() {
    setState(() {
      _messages.clear();
      _messages.add({
        'text': '👋 Nouvelle conversation démarrée !',
        'isBot': true,
      });
    });
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

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      _selectedImage = image;
      _imageUrl = null;
    });
  }

  Future<void> _takePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    setState(() {
      _selectedImage = image;
      _imageUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F4), // Fond vert très clair
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A7B5A), // Vert profond
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('💬 Assistant IA', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: _newConversation,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Nouveau'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A7B5A), Color(0xFF1A9B7A)], // Dégradé vert élégant
            stops: [0.0, 0.3],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return const TypingIndicator();
                  }
                  final msg = _messages[index];
                  return MessageBubble(
                    text: msg['text'] ?? '',
                    isBot: msg['isBot'],
                    imagePath: msg['image'],
                  );
                },
              ),
            ),
            // Zone d'aperçu d'image
            if (_selectedImage != null || (_imageUrl != null && _imageUrl!.isNotEmpty))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _selectedImage != null
                          ? Image.file(File(_selectedImage!.path), height: 180, fit: BoxFit.cover)
                          : Image.network(_imageUrl!, height: 180, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.white, shadows: [Shadow(blurRadius: 10)]),
                        onPressed: () => setState(() {
                          _selectedImage = null;
                          _imageUrl = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            // Zone d'entrée
            Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Boutons image
                    Row(
                      children: [
                        IconButton(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.photo_library, color: Color(0xFF0A7B5A)),
                        ),
                        IconButton(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.camera_alt, color: Color(0xFF0A7B5A)),
                        ),
                        // URL à implémenter plus tard
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.link, color: Colors.grey),
                        ),
                        const Spacer(),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: 'Écris ton message...',
                              filled: true,
                              fillColor: const Color(0xFFF5F5F5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FloatingActionButton(
                          onPressed: _sendMessage,
                          backgroundColor: const Color(0xFF0A7B5A),
                          child: const Icon(Icons.send, color: Colors.white),
                        ),
                      ],
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
}

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 8,
            width: 8,
            decoration: const BoxDecoration(color: Color(0xFF0A7B5A), shape: BoxShape.circle),
          )),
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isBot;
  final String? imagePath;

  const MessageBubble({super.key, required this.text, required this.isBot, this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (imagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imagePath!.startsWith('http')
                    ? Image.network(imagePath!, width: 250, height: 250, fit: BoxFit.cover)
                    : Image.file(File(imagePath!), width: 250, height: 250, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isBot ? Colors.white : const Color(0xFF0A7B5A),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: isBot
                  ? MarkdownBody(
                      data: text,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(color: Colors.black87, height: 1.5, fontSize: 15.5),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )
                  : Text(text, style: const TextStyle(color: Colors.white, fontSize: 15.5)),
            ),
          ],
        ),
      ),
    );
  }
}