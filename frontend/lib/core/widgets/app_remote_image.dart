import 'package:flutter/material.dart';

final String _mediaRetryToken =
    DateTime.now().microsecondsSinceEpoch.toString();

/// Returns a new cache key only for images served by Mushukistan media.
String? retryUrlForAppMedia(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host != 'media.mushukistan.uz') {
    return null;
  }
  final query = uri.query.isEmpty
      ? '_retry=$_mediaRetryToken'
      : '${uri.query}&_retry=$_mediaRetryToken';
  return uri.replace(query: query).toString();
}

/// Loads the original URL first and retries a failed app-hosted image once.
class AppRemoteImage extends StatelessWidget {
  const AppRemoteImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    required this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        final retryUrl = retryUrlForAppMedia(url);
        if (retryUrl == null) {
          return errorBuilder(context, error, stackTrace);
        }
        return Image.network(
          retryUrl,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
