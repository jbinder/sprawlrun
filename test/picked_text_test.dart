import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/util/picked_text.dart';

void main() {
  const spanish = 'Los distritos quedaron bajo el agua hace once años; la ciudad lo llamó retirada.';

  test('a picked file is read as UTF-8, not byte by byte', () async {
    // The shape file_selector_android returns: the bytes, not a path.
    final picked = XFile.fromData(Uint8List.fromList(utf8.encode(spanish)), name: 'pack.json');

    expect(await readPickedText(picked), spanish);
  });

  test('a byte-order mark is dropped so the JSON still parses', () {
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('{"title":"Marea baja en The Drowned Mile — año"}')];

    expect(jsonDecode(decodeText(bytes)), {'title': 'Marea baja en The Drowned Mile — año'});
  });

  test('a file that is not UTF-8 is refused rather than garbled', () {
    expect(() => decodeText(latin1.encode('año')), throwsFormatException);
  });
}
