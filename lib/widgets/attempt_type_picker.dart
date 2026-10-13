import 'package:flutter/material.dart';

import '../models/test_record.dart';

const _icons = {
  AttemptType.realFace: Icons.face,
  AttemptType.printedPhoto: Icons.print,
  AttemptType.screenPhoto: Icons.phone_android,
  AttemptType.video: Icons.ondemand_video,
};

/// Asks the tester what they are about to present to the camera.
Future<AttemptType?> pickAttemptType(BuildContext context) {
  return showModalBottomSheet<AttemptType>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'ما نوع هذه المحاولة؟',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final t in AttemptType.values)
            ListTile(
              leading: Icon(_icons[t]),
              title: Text(t.label),
              onTap: () => Navigator.of(context).pop(t),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
