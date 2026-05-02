import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/support_ticket_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/animated_background.dart';

class SupportTicketsPage extends StatefulWidget {
  final bool asDialog;

  const SupportTicketsPage({super.key, this.asDialog = false});

  static Future<void> showModal(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: Localizations.localeOf(context).languageCode == 'tr'
          ? 'Destek'
          : 'Support',
      barrierColor: Colors.black.withOpacity(0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        final size = MediaQuery.sizeOf(context);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: size.width < 460 ? size.width - 28 : 430,
              height: size.height < 760 ? size.height - 72 : 680,
              child: const SupportTicketsPage(asDialog: true),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends State<SupportTicketsPage> {
  final SupportTicketService _service = SupportTicketService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  int _remainingToday = 3;
  int _dailyLimit = 3;
  List<Map<String, dynamic>> _tickets = <Map<String, dynamic>>[];

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';
  String _text(String tr, String en) => _isTurkish ? tr : en;

  AppThemeConfig _currentTheme() {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.listTickets();
      if (!mounted) return;
      setState(() {
        _tickets = (data['tickets'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _remainingToday = (data['remainingToday'] as num?)?.toInt() ?? 0;
        _dailyLimit = (data['dailyLimit'] as num?)?.toInt() ?? 3;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Ticket listesi yuklenemedi: $e',
            'The ticket list could not be loaded: $e',
          )),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openCreateDialog() async {
    final selectedTheme = _currentTheme();
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    var type = 'REQUEST';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor:
                  selectedTheme.colors.background.withOpacity(0.96),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: selectedTheme.colors.accent.withOpacity(0.36),
                ),
              ),
              title: Text(
                _text('Yeni Ticket', 'New Ticket'),
                style: const TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      dropdownColor: selectedTheme.colors.background,
                      decoration: InputDecoration(
                        labelText: _text('Tur', 'Type'),
                        labelStyle: const TextStyle(color: Colors.white70),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: selectedTheme.colors.accent),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'REQUEST',
                          child: Text(_text('Istek', 'Request')),
                        ),
                        DropdownMenuItem(
                          value: 'COMPLAINT',
                          child: Text(_text('Sikayet', 'Complaint')),
                        ),
                        DropdownMenuItem(
                          value: 'BUG',
                          child: Text(_text('Hata', 'Bug')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => type = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _text('Baslik', 'Title'),
                        labelStyle: const TextStyle(color: Colors.white70),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: selectedTheme.colors.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: messageController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: _text('Mesaj', 'Message'),
                        labelStyle: const TextStyle(color: Colors.white70),
                        alignLabelWithHint: true,
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: selectedTheme.colors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _text('Iptal', 'Cancel'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedTheme.colors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final message = messageController.text.trim();
                          if (title.isEmpty || message.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(_text(
                                  'Baslik ve mesaj gerekli.',
                                  'Title and message are required.',
                                )),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          await _submitTicket(
                            type: type,
                            title: title,
                            message: message,
                          );
                        },
                  child: Text(_text('Gonder', 'Submit')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitTicket({
    required String type,
    required String title,
    required String message,
  }) async {
    setState(() => _isSubmitting = true);
    try {
      final data = await _service.createTicket(
        type: type,
        title: title,
        message: message,
        locale: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() {
        _remainingToday = (data['remainingToday'] as num?)?.toInt() ?? 0;
        _dailyLimit = (data['dailyLimit'] as num?)?.toInt() ?? 3;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Ticket gonderildi.',
            'Your ticket has been submitted.',
          )),
          backgroundColor: Colors.green,
        ),
      );
    } on SupportTicketException catch (e) {
      if (!mounted) return;
      final message = e.statusCode == 429
          ? _text(
              'Bugun icin 3 ticket hakkini doldurdun.',
              'You have reached the 3-ticket daily limit.',
            )
          : _text(
              'Ticket gonderilemedi: ${e.message}',
              'The ticket could not be submitted: ${e.message}',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme();
    final content = Stack(
      children: [
        const AnimatedBackground(isDark: true),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        widget.asDialog ? Icons.close : Icons.arrow_back,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _text('Destek Ticketlari', 'Support Tickets'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedTheme.colors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withOpacity(0.10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _remainingToday > 0 && !_isSubmitting
                          ? _openCreateDialog
                          : null,
                      child: Text(_text('Yeni', 'New')),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        selectedTheme.colors.cardBackground.withOpacity(0.58),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedTheme.colors.glassBorder.withOpacity(0.72),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(
                          'Gunluk hak: $_remainingToday / $_dailyLimit',
                          'Daily quota: $_remainingToday / $_dailyLimit',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _text(
                          'Ticketlar 7 gun tutulur ve sonra otomatik silinir.',
                          'Tickets are kept for 7 days and then deleted automatically.',
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _tickets.isEmpty
                        ? Center(
                            child: Text(
                              _text(
                                'Henuz ticket olusturmadin.',
                                'You have not created any tickets yet.',
                              ),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            itemBuilder: (context, index) {
                              final ticket = _tickets[index];
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: selectedTheme.colors.cardBackground
                                      .withOpacity(0.58),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selectedTheme.colors.glassBorder
                                        .withOpacity(0.72),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selectedTheme.colors.accent
                                                .withOpacity(0.16),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            ticket['type']?.toString() ??
                                                'REQUEST',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          ticket['status']?.toString() ??
                                              'OPEN',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      ticket['title']?.toString() ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      ticket['message']?.toString() ?? '',
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemCount: _tickets.length,
                          ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.asDialog) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selectedTheme.colors.background.withOpacity(0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selectedTheme.colors.accent.withOpacity(0.34),
            ),
          ),
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
    );
  }
}
