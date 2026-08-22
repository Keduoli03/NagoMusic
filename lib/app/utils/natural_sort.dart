import 'package:lpinyin/lpinyin.dart';

String naturalPinyinSortKey(String text, {Map<String, String>? cache}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  final cached = cache?[trimmed];
  if (cached != null) return cached;
  final pinyin = PinyinHelper.getPinyin(
    trimmed,
    separator: '',
    format: PinyinFormat.WITHOUT_TONE,
  );
  final key = (pinyin.isNotEmpty ? pinyin : trimmed).toLowerCase();
  cache?[trimmed] = key;
  return key;
}

int naturalPinyinCompare(String a, String b, {Map<String, String>? cache}) {
  return naturalCompare(
    naturalPinyinSortKey(a, cache: cache),
    naturalPinyinSortKey(b, cache: cache),
  );
}

int naturalCompare(String a, String b) {
  final left = a.toLowerCase();
  final right = b.toLowerCase();
  var leftIndex = 0;
  var rightIndex = 0;

  while (leftIndex < left.length && rightIndex < right.length) {
    final leftCode = left.codeUnitAt(leftIndex);
    final rightCode = right.codeUnitAt(rightIndex);
    final leftIsDigit = _isAsciiDigit(leftCode);
    final rightIsDigit = _isAsciiDigit(rightCode);

    if (leftIsDigit && rightIsDigit) {
      final numberCompare = _compareNumberRuns(
        left,
        leftIndex,
        right,
        rightIndex,
      );
      if (numberCompare.result != 0) return numberCompare.result;
      leftIndex = numberCompare.nextLeftIndex;
      rightIndex = numberCompare.nextRightIndex;
      continue;
    }

    if (leftCode != rightCode) return leftCode.compareTo(rightCode);
    leftIndex += 1;
    rightIndex += 1;
  }

  return (left.length - leftIndex).compareTo(right.length - rightIndex);
}

_NumberRunCompare _compareNumberRuns(
  String left,
  int leftStart,
  String right,
  int rightStart,
) {
  final leftEnd = _digitRunEnd(left, leftStart);
  final rightEnd = _digitRunEnd(right, rightStart);
  final leftTrimmed = _skipLeadingZeroes(left, leftStart, leftEnd);
  final rightTrimmed = _skipLeadingZeroes(right, rightStart, rightEnd);
  final leftLength = leftEnd - leftTrimmed;
  final rightLength = rightEnd - rightTrimmed;

  if (leftLength != rightLength) {
    return _NumberRunCompare(
      leftLength.compareTo(rightLength),
      leftEnd,
      rightEnd,
    );
  }

  for (var i = 0; i < leftLength; i += 1) {
    final diff = left
        .codeUnitAt(leftTrimmed + i)
        .compareTo(right.codeUnitAt(rightTrimmed + i));
    if (diff != 0) return _NumberRunCompare(diff, leftEnd, rightEnd);
  }

  final rawLengthCompare = (leftEnd - leftStart).compareTo(
    rightEnd - rightStart,
  );
  return _NumberRunCompare(rawLengthCompare, leftEnd, rightEnd);
}

int _digitRunEnd(String value, int start) {
  var index = start;
  while (index < value.length && _isAsciiDigit(value.codeUnitAt(index))) {
    index += 1;
  }
  return index;
}

int _skipLeadingZeroes(String value, int start, int end) {
  var index = start;
  while (index < end - 1 && value.codeUnitAt(index) == 48) {
    index += 1;
  }
  return index;
}

bool _isAsciiDigit(int code) => code >= 48 && code <= 57;

class _NumberRunCompare {
  final int result;
  final int nextLeftIndex;
  final int nextRightIndex;

  const _NumberRunCompare(this.result, this.nextLeftIndex, this.nextRightIndex);
}
