import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/features/add_observation/presentation/screens/publish_success_screen.dart';

void main() {
  testWidgets('published observation success shows photo preview',
      (tester) async {
    final post = PostDetail(
      id: 'post-1',
      cat: const PostCatData(id: 'cat-1', status: 'unknown', name: 'Mittens'),
      photoUrl: 'https://storage.example/posts/original/post.jpg',
      photoUrls: const ['https://storage.example/posts/original/post.jpg'],
      thumbUrl: 'https://storage.example/posts/thumbs/post.jpg',
      location: const GeoPoint(latitude: 41.3, longitude: 69.25),
      createdAt: DateTime.utc(2026, 8, 14),
      likeCount: 0,
      commentCount: 0,
      isLikedByMe: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PublishSuccessScreen(post: post),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, post.thumbUrl);
  });
}
