import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FleetKeyboard extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback? onDelete;
  final VoidCallback? onEnter;

  const FleetKeyboard({
    Key? key,
    required this.onKeyPressed,
    this.onDelete,
    this.onEnter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 0: Text being entered by user (displayed in dialog, not here)
          // Row 1: 7, 8, 9
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('7', () => onKeyPressed('7')),
              _buildKey('8', () => onKeyPressed('8')),
              _buildKey('9', () => onKeyPressed('9')),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: 4, 5, 6
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('4', () => onKeyPressed('4')),
              _buildKey('5', () => onKeyPressed('5')),
              _buildKey('6', () => onKeyPressed('6')),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: 1, 2, 3
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('1', () => onKeyPressed('1')),
              _buildKey('2', () => onKeyPressed('2')),
              _buildKey('3', () => onKeyPressed('3')),
            ],
          ),
          const SizedBox(height: 8),
          // Row 4: A, 0, Backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKey('A', () => onKeyPressed('A')),
              _buildKey('0', () => onKeyPressed('0')),
              _buildKey('⌫', onDelete ?? () {}, isSpecial: true), // Backspace symbol
            ],
          ),
          // Row 5: "Done" Button (handled in dialog, not here)
        ],
      ),
    );
  }

  Widget _buildKey(String label, VoidCallback onTap, {bool isSpecial = false}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isSpecial ? Colors.orange.shade300 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSpecial ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: isSpecial ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class FleetKeyboardDialog extends StatefulWidget {
  final TextEditingController controller;
  final int maxLength;

  const FleetKeyboardDialog({
    Key? key,
    required this.controller,
    this.maxLength = 4,
  }) : super(key: key);

  @override
  State<FleetKeyboardDialog> createState() => _FleetKeyboardDialogState();
}

class _FleetKeyboardDialogState extends State<FleetKeyboardDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Display current value
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                widget.controller.text.toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Custom keyboard
            FleetKeyboard(
              onKeyPressed: (key) {
                if (widget.controller.text.length < widget.maxLength) {
                  setState(() {
                    widget.controller.text += key;
                  });
                }
              },
              onDelete: () {
                if (widget.controller.text.isNotEmpty) {
                  setState(() {
                    widget.controller.text = widget.controller.text
                        .substring(0, widget.controller.text.length - 1);
                  });
                }
              },
              onEnter: () {
                Navigator.of(context).pop(widget.controller.text);
              },
            ),
            const SizedBox(height: 16),
            // Done button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(widget.controller.text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0081FB),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: Color(0xFFFEFE00),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

