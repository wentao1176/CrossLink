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

const _receiptRank = {'sent': 0, 'pending': 1, 'delivered': 2, 'read': 3};

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
      final previous = _items[index];
      final next = {...previous, ...value};
      if ((_receiptRank[previous['status']] ?? -1) >
          (_receiptRank[next['status']] ?? -1)) {
        next['status'] = previous['status'];
      }
      _items[index] = next;
      return false;
    }
    _items.insert(0, Map.of(value));
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    return true;
  }

  bool updateReceipt(String messageId, String status) {
    final index = _items.indexWhere((m) => m['id'] == messageId);
    if (index < 0 || !_receiptRank.containsKey(status)) return false;
    final previous = _items[index]['status'];
    if (previous == status ||
        (_receiptRank[previous] ?? -1) > _receiptRank[status]!) {
      return false;
    }
    _items[index] = {..._items[index], 'status': status};
    return true;
  }

  void clear() => _items.clear();
}

String deviceProfileKey(String endpoint, String account) =>
    'device_uuid_${Uri.parse(endpoint).origin.toLowerCase()}_${account.trim().toLowerCase()}';
