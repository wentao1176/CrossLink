import 'dart:math';

String normalizeEndpoint(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('请输入完整服务器地址，例如 https://sync.example.com');
  }
  if (uri.scheme == 'http' &&
      !['127.0.0.1', 'localhost', '::1'].contains(uri.host)) {
    throw const FormatException('公网连接请使用 HTTPS；HTTP 仅用于本机 SSH 隧道');
  }
  return uri.origin;
}

int reconnectSeconds(int attempt) => min(30, 1 << min(5, max(0, attempt)));

class MessageCache {
  MessageCache({this.maxItems = 100});
  final int maxItems;
  final List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);
  bool put(Map<String, dynamic> value) {
    final id = value['id'];
    if (id is! String || id.isEmpty) return false;
    final index = _items.indexWhere((m) => m['id'] == id);
    if (index >= 0) {
      _items[index] = {..._items[index], ...value};
      return false;
    }
    _items.insert(0, Map.of(value));
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    return true;
  }

  void clear() => _items.clear();
}

String deviceProfileKey(String endpoint, String account) =>
    'device_uuid_${Uri.parse(endpoint).origin.toLowerCase()}_${account.trim().toLowerCase()}';
