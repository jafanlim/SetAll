import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareFiles(
  List<XFile> files, {
  required BuildContext context,
  String? subject,
  GlobalKey? originKey,
}) async {
  Rect? originRect;
  if (originKey?.currentContext != null) {
    final box = originKey!.currentContext!.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      originRect = pos & box.size;
    }
  }
  if (originRect == null || originRect == Rect.zero) {
    final size = MediaQuery.sizeOf(context);
    originRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 4),
      width: 1,
      height: 1,
    );
  }
  await Share.shareXFiles(
    files,
    subject: subject,
    sharePositionOrigin: originRect,
  );
}
