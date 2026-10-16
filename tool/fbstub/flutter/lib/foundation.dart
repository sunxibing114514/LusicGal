// 最小 foundation 桩（JVM 级逻辑 harness 用）：
// 仅覆盖 LibraryStore 所需符号；真运行期由 Flutter 提供。
typedef VoidCallback = void Function();

class Protected {
  const Protected();
}

class VisibleForTesting {
  const VisibleForTesting();
}

const protected = Protected();
const visibleForTesting = VisibleForTesting();

class ChangeNotifier {
  final List<VoidCallback> _listeners = [];
  bool _disposed = false;

  void addListener(VoidCallback listener) {
    if (!_disposed) _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  @protected
  void notifyListeners() {
    if (_disposed) return;
    for (final l in List<VoidCallback>.of(_listeners)) {
      l();
    }
  }

  void dispose() {
    _listeners.clear();
    _disposed = true;
  }
}
