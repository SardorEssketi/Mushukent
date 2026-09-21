import 'package:web/web.dart' as web;

void releaseBlobUrl(String path) {
  if (path.startsWith('blob:')) {
    web.URL.revokeObjectURL(path);
  }
}
