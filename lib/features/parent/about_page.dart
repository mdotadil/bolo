import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/policy_service.dart';
import '../../theme.dart';
import '../board/board_providers.dart';

/// Parent-mode "About and privacy" page. Loads the privacy text through
/// [PolicyService] (network fetch happens only because this page was
/// opened — never at app start) and renders it with a tiny hand-rolled
/// renderer: no markdown package, just `# `/`- ` line prefixes.
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key, this.policyService});

  /// Injectable for tests; defaults to a real [PolicyService] built from the
  /// app's docs directory.
  final PolicyService? policyService;

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  late final Future<String> _future;

  @override
  void initState() {
    super.initState();
    final service =
        widget.policyService ?? PolicyService(ref.read(docsDirProvider));
    _future = service.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About and privacy')),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            // The fallback chain in PolicyService never throws, so this is
            // always a transient "still loading" state, never an error.
            return const Center(
              child: Text('Loading…',
                  key: ValueKey('about-loading'),
                  style: TextStyle(color: BoloTheme.text)),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(16),
            child: _PolicyBody(text: snapshot.data!),
          );
        },
      ),
    );
  }
}

/// Renders privacy-policy plain text: `# ` lines become bold headings, `- `
/// lines become bullet rows, blank lines become spacing, everything else is
/// a body paragraph.
class _PolicyBody extends StatelessWidget {
  const _PolicyBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 12));
      } else if (line.startsWith('# ')) {
        children.add(Padding(
          padding: const EdgeInsetsDirectional.only(top: 4, bottom: 4),
          child: Text(
            line.substring(2).trim(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: BoloTheme.text,
            ),
          ),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(color: BoloTheme.text)),
              Expanded(
                child: Text(line.substring(2).trim(),
                    style: const TextStyle(color: BoloTheme.text)),
              ),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 4),
          child: Text(line, style: const TextStyle(color: BoloTheme.text)),
        ));
      }
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
