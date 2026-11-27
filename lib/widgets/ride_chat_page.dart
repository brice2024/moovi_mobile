import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/messaging_service.dart';
import '../services/session.dart';

/// Discussion en temps réel entre le passager et le chauffeur d'une course.
class RideChatPage extends StatefulWidget {
  final String rideId;
  final String title;
  const RideChatPage({super.key, required this.rideId, required this.title});

  /// Course dont la discussion est affichée (évite un bandeau redondant).
  static String? openRideId;

  @override
  State<RideChatPage> createState() => _RideChatPageState();
}

class _RideChatPageState extends State<RideChatPage> {
  static const _orange = Color(0xFFFF7A00);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String? get _myId => AppSession.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    RideChatPage.openRideId = widget.rideId;
    _sub = MessagingService.instance.messagesStream(widget.rideId).listen(
      (list) {
        if (!mounted) return;
        final grew = list.length > _messages.length;
        setState(() {
          _messages = list;
          _loading = false;
          _error = null;
        });
        if (grew) _scrollToEnd();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = errorMessage(e);
        });
      },
    );
  }

  @override
  void dispose() {
    if (RideChatPage.openRideId == widget.rideId) RideChatPage.openRideId = null;
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg =
          await MessagingService.instance.sendMessage(widget.rideId, text);
      _input.clear();
      if (!mounted) return;
      setState(() => _messages = MessagingService.mergeMessage(_messages, msg));
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _time(dynamic iso) {
    final d = asDate(iso);
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        title: Text(widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Expanded(child: _buildList()),
        SafeArea(
          top: false,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Votre message…',
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF1F1F4),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: _orange),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _orange));
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('Aucun message. Écrivez le premier !',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final mine = m['senderUserId']?.toString() == _myId;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine ? _orange : Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(m['content']?.toString() ?? '',
                    style: TextStyle(
                        color: mine ? Colors.white : Colors.black,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(_time(m['createdAt']),
                    style: TextStyle(
                        color: mine ? Colors.white70 : Colors.grey,
                        fontSize: 10)),
              ],
            ),
          ),
        );
      },
    );
  }
}
