import 'package:flutter/widgets.dart';

import '../../../../core/widgets/empty_screen.dart';

class CatDetailScreen extends StatelessWidget {
  const CatDetailScreen({super.key, required this.catId});

  final String catId;

  @override
  Widget build(BuildContext context) {
    return EmptyScreen(title: 'Cat Detail: $catId');
  }
}
