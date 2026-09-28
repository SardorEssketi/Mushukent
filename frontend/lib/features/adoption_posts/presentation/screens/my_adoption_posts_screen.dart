import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';

class MyAdoptionPostsScreen extends ConsumerStatefulWidget {
  const MyAdoptionPostsScreen({super.key});

  @override
  ConsumerState<MyAdoptionPostsScreen> createState() =>
      _MyAdoptionPostsScreenState();
}

class _MyAdoptionPostsScreenState extends ConsumerState<MyAdoptionPostsScreen> {
  final List<AdoptionPostData> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _loaded = false;
  bool _error = false;
  bool _resetQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (!mounted) return;
    if (_loading) {
      if (reset) _resetQueued = true;
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
      if (reset) _cursor = null;
    });
    try {
      final page = await ref.read(mushukistanApiProvider).listMyAdoptionPosts(
            cursor: _cursor,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_resetQueued) {
          _resetQueued = false;
          unawaited(_load(reset: true));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final overrides = ref.watch(adoptionMutationOverridesProvider);
    final deletedIds = ref.watch(deletedAdoptionIdsProvider);
    ref.listen<int>(postMutationRevisionProvider, (previous, next) {
      if (previous != next) _load(reset: true);
    });
    final visibleItems = _items
        .where((post) => !deletedIds.contains(post.id))
        .map((post) => overrides[post.id] ?? post)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(strings.myAdoptionPosts)),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loaded && visibleItems.isEmpty)
              Text(strings.noAdoptionPostsYet),
            for (final post in visibleItems)
              Card(
                child: ListTile(
                  leading: Image.network(
                    post.thumbUrl ?? post.photoUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.pets),
                  ),
                  title: Text(post.petName),
                  subtitle: Text(post.isResolved
                      ? strings.rehomedAdoptionPost
                      : strings.activeAdoptionPost),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/adoption-posts/${post.id}'),
                ),
              ),
            if (_error)
              TextButton(
                onPressed: () => _load(reset: !_loaded),
                child: Text(strings.retry),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _cursor != null)
              TextButton(
                  onPressed: _load, child: Text(strings.loadMoreAdoptionPosts)),
          ],
        ),
      ),
    );
  }
}
