import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/support_ticket_service.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// Where a learner writes to a person.
///
/// The service behind this has existed for a long time and had no door. The
/// only ways to reach it were a small "this content is wrong" control that
/// appears beside a sentence mid-exercise, and a sheet the app opens by itself
/// after a third completed practice — both of which are about the content.
/// Someone charged twice, locked out of their account, or wanting their data
/// deleted had nowhere at all to go, and Google Play requires a route for the
/// last of those.
///
/// The email is shown as well as the form, and not as a nicety: [SupportTicketService]
/// throws `missing-auth-context` without a signed-in user, so the person most
/// likely to need help — the one who cannot log in — is exactly the person the
/// form cannot serve. It is selectable text rather than a link because this app
/// has no url_launcher dependency, and adding one to open a mail client is a
/// larger change than showing an address someone can copy.
class NfSupportPage extends StatefulWidget {
  const NfSupportPage({super.key, this.service});

  /// Injectable for tests.
  final SupportTicketService? service;

  /// The mailbox that is actually read. Kept here rather than in the
  /// localisation map: it is the same address in every language, and a
  /// translated copy of it is a copy that can drift.
  static const String email = 'erenulutas193@gmail.com';

  @override
  State<NfSupportPage> createState() => _NfSupportPageState();
}

/// The ticket types the backend accepts that a person would choose for
/// themselves. CONTENT_REPORT and FEEDBACK are missing on purpose — both are
/// already raised from where the content is, with the sentence attached, which
/// is far more useful than the same words typed out here from memory.
enum _SupportKind {
  bug('BUG', 'support.type.bug', Icons.bug_report_outlined),
  complaint('COMPLAINT', 'support.type.complaint', Icons.flag_outlined),
  request('REQUEST', 'support.type.request', Icons.lightbulb_outline),
  deletion('ACCOUNT_DELETION', 'support.type.deletion',
      Icons.delete_outline_rounded);

  const _SupportKind(this.wire, this.labelKey, this.icon);

  /// What the server's TicketType enum calls this.
  final String wire;
  final String labelKey;
  final IconData icon;
}

class _NfSupportPageState extends State<NfSupportPage> {
  late final SupportTicketService _service =
      widget.service ?? SupportTicketService();
  final TextEditingController _message = TextEditingController();

  _SupportKind _kind = _SupportKind.bug;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _message.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _service.createTicket(
        type: _kind.wire,
        // The server wants a title; a person writing to support wants to write
        // one thing, not two. The first line of what they wrote is the honest
        // subject, and the whole message goes in the body regardless.
        title: _subjectFrom(text),
        message: text,
        locale: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = context.tr('support.error');
      });
    }
  }

  static String _subjectFrom(String message) {
    final String firstLine = message.split('\n').first.trim();
    return firstLine.length <= 80 ? firstLine : firstLine.substring(0, 80);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(t),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    NfSpace.s16, NfSpace.s8, NfSpace.s16, NfSpace.s26),
                children: <Widget>[
                  if (_sent) _buildSent(t) else ..._buildForm(t),
                  const SizedBox(height: NfSpace.s16),
                  _buildEmailCard(t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          NfSpace.s12, NfSpace.s8, NfSpace.s16, NfSpace.s4),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: NfFont.s22,
            color: t.ink,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('support.title'),
                  style: NfTokens.display(size: NfFont.s20, color: t.ink),
                ),
                Text(
                  context.tr('support.subtitle'),
                  style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildForm(NfTokens t) {
    return <Widget>[
      NfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: NfSpace.s6,
              runSpacing: NfSpace.s6,
              children: <Widget>[
                for (final _SupportKind kind in _SupportKind.values)
                  NfChip(
                    label: context.tr(kind.labelKey),
                    icon: kind.icon,
                    dense: true,
                    variant: kind == _kind
                        ? NfChipVariant.selected
                        : NfChipVariant.unselected,
                    onTap: _sending ? null : () => setState(() => _kind = kind),
                  ),
              ],
            ),
            if (_kind == _SupportKind.deletion) ...<Widget>[
              const SizedBox(height: NfSpace.s10),
              Text(
                context.tr('support.deletion.note'),
                style: NfTokens.body(size: NfFont.s125, color: t.wrong),
              ),
            ],
            const SizedBox(height: NfSpace.s12),
            TextField(
              controller: _message,
              enabled: !_sending,
              minLines: 5,
              maxLines: 10,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: NfTokens.body(size: NfFont.s145, color: t.ink),
              decoration: InputDecoration(
                hintText: context.tr('support.message.hint'),
                hintStyle:
                    NfTokens.body(size: NfFont.s135, color: t.inkFaint),
                filled: true,
                fillColor: t.raised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NfSpace.s12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: NfSpace.s8),
              Text(
                _error!,
                style: NfTokens.body(size: NfFont.s13, color: t.wrong),
              ),
            ],
            const SizedBox(height: NfSpace.s12),
            NfPrimaryButton(
              label: context.tr('support.send'),
              // The label stays put and the button spins in place, so it does
              // not change width mid-send.
              busy: _sending,
              // Disabled on an empty box rather than sending nothing and then
              // showing an error about it.
              onPressed: _message.text.trim().isEmpty || _sending
                  ? null
                  : () => unawaited(_send()),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildSent(NfTokens t) {
    return NfCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline, color: t.correct, size: NfFont.s22),
          const SizedBox(width: NfSpace.s10),
          Expanded(
            child: Text(
              context.tr('support.sent'),
              style: NfTokens.body(size: NfFont.s145, color: t.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailCard(NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('support.email.label'),
            style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
          ),
          const SizedBox(height: NfSpace.s6),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  NfSupportPage.email,
                  style: NfTokens.body(size: NfFont.s145, color: t.ink),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded,
                    size: NfFont.s18, color: t.inkMuted),
                tooltip: MaterialLocalizations.of(context).copyButtonLabel,
                onPressed: () => unawaited(
                  Clipboard.setData(
                      const ClipboardData(text: NfSupportPage.email)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
