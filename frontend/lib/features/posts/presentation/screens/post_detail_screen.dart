import 'package:flutter/widgets.dart';

import '../../../../core/widgets/empty_screen.dart';

class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    return EmptyScreen(title: 'Post Detail: $postId');
  }
}
