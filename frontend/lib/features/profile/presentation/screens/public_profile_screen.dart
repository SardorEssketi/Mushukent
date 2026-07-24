import 'package:flutter/widgets.dart';

import '../../../../core/widgets/empty_screen.dart';

class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return EmptyScreen(title: 'Public Profile: $userId');
  }
}
