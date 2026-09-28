import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';

class MyLostPetsScreen extends ConsumerStatefulWidget {
  const MyLostPetsScreen({super.key});

  @override
  ConsumerState<MyLostPetsScreen> createState() => _MyLostPetsScreenState();
}

class _MyLostPetsScreenState extends ConsumerState<MyLostPetsScreen> {
  final List<LostPetData> _items = [];
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
      if (reset) {
        _cursor = null;
        _items.clear();
      }
    });
    try {
      final page = await ref.read(mushukistanApiProvider).listMyLostPets(
            cursor: _cursor,
          );
      if (!mounted) return;
      setState(() {
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
    ref.listen<int>(postMutationRevisionProvider, (previous, next) {
      if (previous != next) _load(reset: true);
    });
    return Scaffold(
      appBar: AppBar(title: Text(strings.myLostPets)),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loaded && _items.isEmpty) Text(strings.noLostPetsYet),
            for (final pet in _items)
              Card(
                child: ListTile(
                  leading: Image.network(
                    pet.thumbUrl ?? pet.photoUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.pets),
                  ),
                  title: Text(pet.petName),
                  subtitle: Text(
                    pet.isResolved
                        ? strings.reunitedLostPet
                        : strings.activeLostPet,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/lost-pets/${pet.id}'),
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
                onPressed: _load,
                child: Text(strings.loadMoreLostPets),
              ),
          ],
        ),
      ),
    );
  }
}
