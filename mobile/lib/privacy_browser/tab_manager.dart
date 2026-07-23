import 'package:flutter/foundation.dart';

import 'browser_tab_model.dart';

class TabManager extends ChangeNotifier {
  TabManager({this.maxTabs = 3}) {
    _tabs.add(BrowserTabModel(id: _nextId()));
  }

  final int maxTabs;
  final List<BrowserTabModel> _tabs = [];
  int _activeIndex = 0;
  int _seq = 0;

  List<BrowserTabModel> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  BrowserTabModel get active => _tabs[_activeIndex];
  bool get canAdd => _tabs.length < maxTabs;

  String _nextId() {
    _seq += 1;
    return 'tab_$_seq';
  }

  void select(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  bool addTab() {
    if (!canAdd) return false;
    _tabs.add(BrowserTabModel(id: _nextId()));
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return true;
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _tabs.add(BrowserTabModel(id: _nextId()));
      _activeIndex = 0;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (_activeIndex > index) {
      _activeIndex -= 1;
    }
    notifyListeners();
  }

  void closeActive() => closeTab(_activeIndex);

  /// Destroy every tab session and open one blank tab (fresh process pools).
  void hardResetTabs() {
    _tabs
      ..clear()
      ..add(BrowserTabModel(id: _nextId()));
    _activeIndex = 0;
    notifyListeners();
  }

  void updateActive(void Function(BrowserTabModel tab) fn) {
    fn(active);
    notifyListeners();
  }

  void notifyTabChanged() => notifyListeners();
}
