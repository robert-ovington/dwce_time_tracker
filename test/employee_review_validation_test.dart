/// Unit tests for Submit Employee Review validation logic (comment rules).

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Employee review comment validation', () {
    test('score 1 requires non-empty comment', () {
      expect(isCommentValidForScore(1, null), false);
      expect(isCommentValidForScore(1, ''), false);
      expect(isCommentValidForScore(1, '   '), false);
      expect(isCommentValidForScore(1, 'Good'), true);
    });

    test('score 3 requires non-empty comment', () {
      expect(isCommentValidForScore(3, null), false);
      expect(isCommentValidForScore(3, ''), false);
      expect(isCommentValidForScore(3, 'Exceeds'), true);
    });

    test('score 2 requires empty comment', () {
      expect(isCommentValidForScore(2, null), true);
      expect(isCommentValidForScore(2, ''), true);
      expect(isCommentValidForScore(2, '   '), true);
      expect(isCommentValidForScore(2, 'Any text'), false);
    });
  });
}

/// Mirrors validation used in SubmitEmployeeReviewScreen.
bool isCommentValidForScore(int score, String? comment) {
  final trimmed = comment?.trim() ?? '';
  if (score == 1 || score == 3) {
    return trimmed.isNotEmpty;
  }
  if (score == 2) {
    return trimmed.isEmpty;
  }
  return false;
}
