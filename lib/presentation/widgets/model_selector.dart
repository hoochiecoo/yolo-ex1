// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import '../../models/models.dart';

/// A widget for selecting different YOLO model types
class ModelSelector extends StatelessWidget {
  const ModelSelector({
    super.key,
    required this.selectedModel,
    required this.isModelLoading,
    required this.onModelChanged,
    this.onCustomUrlSubmitted,
  });

  final ModelType selectedModel;
  final bool isModelLoading;
  final ValueChanged<ModelType> onModelChanged;
  final ValueChanged<String>? onCustomUrlSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...ModelType.values.map((model) {
            final isSelected = selectedModel == model;
            return GestureDetector(
              onTap: () {
                if (!isModelLoading && model != selectedModel) {
                  onModelChanged(model);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  model.name.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: isModelLoading
                ? null
                : () async {
                    final controller = TextEditingController();
                    final url = await showDialog<String>(
                      context: context,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text('Custom model URL (.tflite)'),
                          content: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              hintText: 'https://example.com/model.tflite',
                            ),
                            keyboardType: TextInputType.url,
                            autofocus: true,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                final value = controller.text.trim();
                                Navigator.pop(ctx, value);
                              },
                              child: const Text('Load'),
                            ),
                          ],
                        );
                      },
                    );
                    if (url != null && url.isNotEmpty) {
                      onCustomUrlSubmitted?.call(url);
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white70, width: 1),
              ),
              child: const Text(
                'CUSTOM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
