import 'dart:async';

import 'package:flutter/material.dart';

/// 全局顶部通知：成功/提示默认两秒，触碰暂停，可上滑关闭。
class Notice {
  final String text;
  final bool error;
  final String? action;
  final VoidCallback? onAction;
  final String id = UniqueKey().toString();
  Notice(this.text, {this.error = false, this.action, this.onAction});
}

final notices = ValueNotifier<List<Notice>>([]);
void notifyApp(
  String text, {
  bool error = false,
  String? action,
  VoidCallback? onAction,
}) {
  if (notices.value.any((n) => n.text == text)) return;
  final queue = [
    ...notices.value,
    Notice(text, error: error, action: action, onAction: onAction),
  ];
  // 队列有界；高频重复由文字合并，优先保留带操作和失败事件。
  if (queue.length > 20) {
    final i = queue.indexWhere((n) => !n.error && n.action == null);
    queue.removeAt(i < 0 ? 0 : i);
  }
  notices.value = queue;
}

void dismissNotice(Notice n) =>
    notices.value = notices.value.where((v) => v != n).toList();

class NoticeHost extends StatelessWidget {
  final Widget child;
  const NoticeHost({super.key, required this.child});
  @override
  Widget build(BuildContext c) => Stack(
    children: [
      child,
      Positioned(
        top: MediaQuery.paddingOf(c).top + 12,
        left: 16,
        right: 16,
        child: ValueListenableBuilder<List<Notice>>(
          valueListenable: notices,
          builder: (c, items, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final n in items.take(3))
                _NoticeCard(key: ValueKey(n.id), notice: n),
            ],
          ),
        ),
      ),
    ],
  );
}

class _NoticeCard extends StatefulWidget {
  final Notice notice;
  const _NoticeCard({super.key, required this.notice});
  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? timer;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    animation.forward();
    start();
  }

  void start() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 2), close);
  }

  Future<void> close() async {
    if (closing) return;
    closing = true;
    timer?.cancel();
    await animation.reverse();
    dismissNotice(widget.notice);
  }

  @override
  void dispose() {
    timer?.cancel();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final n = widget.notice, scheme = Theme.of(c).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 5,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  n.error ? Icons.error_outline : Icons.check_circle_outline,
                  color: n.error ? scheme.error : scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    n.text,
                    style: TextStyle(fontSize: 14, color: scheme.onSurface),
                  ),
                ),
                if (n.action != null)
                  TextButton(
                    onPressed: () {
                      n.onAction?.call();
                      close();
                    },
                    child: Text(n.action!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Listener(
      onPointerDown: (_) => timer?.cancel(),
      onPointerUp: (_) => start(),
      onPointerCancel: (_) => start(),
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -100) {
            close();
          } else {
            start();
          }
        },
        child: MediaQuery.disableAnimationsOf(c)
            ? content
            : FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, -.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: content,
                ),
              ),
      ),
    );
  }
}
