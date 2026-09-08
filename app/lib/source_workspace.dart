import 'package:flutter/material.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'central_email_api.dart';

/// Read-only Reader adapter. Each body is fetched on selection, never as a batch.
class ReaderSourceWorkspace extends StatefulWidget {
  const ReaderSourceWorkspace({super.key, required this.api});
  final CentralEmailApi api;
  @override
  State<ReaderSourceWorkspace> createState() => _ReaderSourceWorkspaceState();
}

class _ReaderSourceWorkspaceState extends State<ReaderSourceWorkspace> {
  final List<SourceSidebarItem> _items = [];
  String? _cursor, _selected, _error;
  bool _loading = false, _configured = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  SourceSidebarItem _item(Map<String, dynamic> item) => SourceSidebarItem(
    id: item['id'] as String,
    title: item['title'] as String,
    authorOrPublisher: item['author'] as String,
    summary: item['summary'] as String,
    content: (item['content'] as String?)?.isNotEmpty == true
        ? item['content'] as String
        : 'Ouvrez cette source pour charger son contenu.',
    publishedAt:
        DateTime.tryParse(item['published_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    sourceType: 'Readwise Reader',
    location: item['location'] as String? ?? 'new',
    canonicalExternalUrl: Uri.https('read.readwise.io', '/read/${item['id']}'),
  );

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.get('sources', {
        if (more && _cursor != null) 'cursor': _cursor!,
      });
      final items = (response['documents'] as List)
          .map((e) => _item(e as Map<String, dynamic>))
          .toList();
      if (!mounted || generation != _generation) return;
      setState(() {
        _configured = response['configured'] == true;
        if (!more) {
          _items.clear();
          _selected = null;
        }
        final ids = _items.map((e) => e.id).toSet();
        _items.addAll(items.where((e) => ids.add(e.id)));
        _cursor = response['next_cursor'] as String?;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is EmailApiException
              ? error.message
              : 'Impossible de charger Reader. Réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? id) async {
    setState(() {
      _selected = id;
      _error = null;
    });
    if (id == null) return;
    final generation = _generation;
    try {
      final result = await widget.api.get('sources', {'id': id});
      if (!mounted || generation != _generation || _selected != id) return;
      final documents = result['documents'] as List;
      if (documents.isEmpty) throw const EmailApiException('not_found');
      final index = _items.indexWhere((e) => e.id == id);
      if (index >= 0) {
        setState(
          () => _items[index] = _item(documents.first as Map<String, dynamic>),
        );
      }
    } catch (error) {
      if (mounted && _selected == id) {
        setState(
          () => _error = error is EmailApiException
              ? error.message
              : 'Le contenu est indisponible. Réessayez.',
        );
      }
    }
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Reader indisponible');
    }
  }

  @override
  Widget build(BuildContext context) => SourceSidebar(
    title: 'Sources',
    items: _items,
    selectedId: _selected,
    onSelected: _select,
    onRefresh: _load,
    isLoading: _loading && _items.isEmpty,
    isLoadingMore: _loading && _items.isNotEmpty,
    hasMore: _cursor != null,
    onLoadMore: () => _load(more: true),
    errorMessage: _error,
    emptyMessage: _configured
        ? 'Aucun email dans votre bibliothèque Reader.'
        : 'Readwise Reader n’est pas encore connecté à cet environnement.',
    onOpenLibrary: () => _open(Uri.https('read.readwise.io', '/')),
    onOpenExternal: (item) => _open(item.canonicalExternalUrl!),
    onActionError: (_) =>
        setState(() => _error = 'Impossible d’ouvrir Reader.'),
  );
}
