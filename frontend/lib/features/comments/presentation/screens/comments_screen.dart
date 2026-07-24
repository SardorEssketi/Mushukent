import 'package:flutter/widgets.dart';

import '../../../../core/widgets/empty_screen.dart';

class CommentsScreen extends StatelessWidget {
  const CommentsScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    return EmptyScreen(title: 'Comments: $postId');
  }
}
