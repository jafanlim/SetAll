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
  await Share.shareXFiles(
    files,
    subject: subject,
    sharePositionOrigin: originRect ?? Rect.zero,
  );
}
