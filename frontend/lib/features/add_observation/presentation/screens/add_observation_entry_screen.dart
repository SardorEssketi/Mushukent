import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddObservationEntryScreen extends StatelessWidget {
  const AddObservationEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.go('/add');
      }
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
