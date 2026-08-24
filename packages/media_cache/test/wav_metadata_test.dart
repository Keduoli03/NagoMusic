import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_cache/media_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WAV embedded ID3 overrides LIST metadata and reads artwork', () async {
    final tempDir = await Directory.systemTemp.createTemp('nago_wav_test_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File('${tempDir.path}${Platform.pathSeparator}fixture.wav');
    await file.writeAsBytes(_buildWavFixture());

    final result = await TagProbeService.instance.probeSong(
      uri: file.path,
      isLocal: true,
      includeArtwork: true,
    );

    expect(result, isNotNull);
    expect(result!.title, '反逆する風景');
    expect(result.artist, 'toe');
    expect(result.album, 'The Book');
    expect(result.trackNumber, 1);
    expect(result.discNumber, 2);
    expect(result.bitrate, 1411200);
    expect(result.sampleRate, 44100);
    expect(result.artwork, orderedEquals(_artworkBytes));
  });

  test('partial WAV head and tail ranges provide complementary metadata', () {
    final tempDir = Directory.systemTemp.createTempSync('nago_wav_range_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final fixture = _buildWavFixture();
    final head = File('${tempDir.path}${Platform.pathSeparator}head.wav')
      ..writeAsBytesSync(fixture.sublist(0, 64));
    final tail = File('${tempDir.path}${Platform.pathSeparator}tail.wav')
      ..writeAsBytesSync(fixture.sublist(100));

    final technical = extractWavTechnicalMetadata(head.path);
    final tags = extractWavId3MetadataFromTail(tail.path, includeArtwork: true);

    expect(technical?.durationMs, 10);
    expect(technical?.bitrate, 1411200);
    expect(technical?.sampleRate, 44100);
    expect(tags?.title, '反逆する風景');
    expect(tags?.artist, 'toe');
    expect(tags?.artwork, orderedEquals(_artworkBytes));
  });

  test('remote WAV probing uses small head and tail ranges', () async {
    final fixture = _buildWavFixture(dataLength: 3 * 1024 * 1024);
    final supportDir = await Directory.systemTemp.createTemp(
      'nago_wav_remote_test_',
    );
    final originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(supportDir.path);
    final originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final ranges = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.set('accept-ranges', 'bytes');
      if (request.method == 'HEAD') {
        request.response.contentLength = fixture.length;
        await request.response.close();
        return;
      }

      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range ?? '');
      var start = 0;
      var end = fixture.length - 1;
      if (range != null && range.startsWith('bytes=-')) {
        final count = int.parse(range.substring('bytes=-'.length));
        start = (fixture.length - count).clamp(0, fixture.length);
      } else if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring('bytes='.length).split('-');
        start = int.parse(parts.first);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.parse(parts[1]).clamp(start, fixture.length - 1);
        }
      }
      final body = fixture.sublist(start, end + 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${fixture.length}',
      );
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });

    try {
      final result = await TagProbeService.instance.probeSong(
        uri: 'http://${server.address.host}:${server.port}/fixture.wav',
        isLocal: false,
        includeArtwork: true,
      );

      expect(result?.title, '反逆する風景');
      expect(result?.artist, 'toe');
      expect(result?.album, 'The Book');
      expect(result?.durationMs, 17833);
      expect(result?.bitrate, 1411200);
      expect(result?.sampleRate, 44100);
      expect(result?.fileSize, fixture.length);
      expect(result?.artwork, orderedEquals(_artworkBytes));
      expect(ranges, contains('bytes=0-65535'));
      expect(ranges, contains('bytes=-2097152'));
      expect(ranges.where((range) => range.isNotEmpty), hasLength(2));
    } finally {
      await server.close(force: true);
      HttpOverrides.global = originalHttpOverrides;
      PathProviderPlatform.instance = originalPathProvider;
      try {
        await supportDir.delete(recursive: true);
      } on FileSystemException {
        // Windows can briefly retain a streamed response handle after Dio
        // completes; the OS temp directory will clean up the test cache.
      }
    }
  });
}

class _FakePathProvider extends PathProviderPlatform {
  final String path;

  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

final _artworkBytes = Uint8List.fromList([
  0xff,
  0xd8,
  0xff,
  0xe0,
  0x00,
  0x10,
  0x4a,
  0x46,
  0x49,
  0x46,
  0x00,
  0xff,
  0xd9,
]);

Uint8List _buildWavFixture({int dataLength = 1764}) {
  final fmt = BytesBuilder()
    ..add(_uint16le(1))
    ..add(_uint16le(2))
    ..add(_uint32le(44100))
    ..add(_uint32le(176400))
    ..add(_uint16le(4))
    ..add(_uint16le(16));
  final id3 = _buildId3Tag();
  final info = BytesBuilder()
    ..add(ascii.encode('INFO'))
    ..add(_infoField('INAM', 'Wrong title'))
    ..add(_infoField('IART', 'Wrong artist'))
    ..add(_infoField('IPRD', 'Wrong album'));

  final body = BytesBuilder()
    ..add(_riffChunk('fmt ', fmt.toBytes()))
    ..add(_riffChunk('data', Uint8List(dataLength)))
    ..add(_riffChunk('id3 ', id3))
    ..add(_riffChunk('LIST', info.toBytes()));
  final bodyBytes = body.toBytes();
  return Uint8List.fromList([
    ...ascii.encode('RIFF'),
    ..._uint32le(bodyBytes.length + 4),
    ...ascii.encode('WAVE'),
    ...bodyBytes,
  ]);
}

Uint8List _buildId3Tag() {
  final frames = BytesBuilder()
    ..add(_textFrame('TIT2', '反逆する風景'))
    ..add(_textFrame('TPE1', 'toe'))
    ..add(_textFrame('TALB', 'The Book'))
    ..add(_textFrame('TRCK', '1/11'))
    ..add(_textFrame('TPOS', '2/2'))
    ..add(_pictureFrame());
  final frameBytes = frames.toBytes();
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    3,
    0,
    0,
    ..._synchsafe(frameBytes.length),
    ...frameBytes,
  ]);
}

Uint8List _textFrame(String id, String value) {
  final data = Uint8List.fromList([3, ...utf8.encode(value)]);
  return _id3Frame(id, data);
}

Uint8List _pictureFrame() {
  final data = Uint8List.fromList([
    0,
    ...ascii.encode('image/jpeg'),
    0,
    3,
    0,
    ..._artworkBytes,
  ]);
  return _id3Frame('APIC', data);
}

Uint8List _id3Frame(String id, Uint8List data) {
  return Uint8List.fromList([
    ...ascii.encode(id),
    ..._uint32be(data.length),
    0,
    0,
    ...data,
  ]);
}

Uint8List _infoField(String id, String value) {
  final data = Uint8List.fromList([...latin1.encode(value), 0]);
  return _riffChunk(id, data);
}

Uint8List _riffChunk(String id, Uint8List data) {
  return Uint8List.fromList([
    ...ascii.encode(id),
    ..._uint32le(data.length),
    ...data,
    if (data.length.isOdd) 0,
  ]);
}

Uint8List _uint16le(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

Uint8List _uint32le(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

Uint8List _uint32be(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);
}

Uint8List _synchsafe(int value) {
  return Uint8List.fromList([
    (value >> 21) & 0x7f,
    (value >> 14) & 0x7f,
    (value >> 7) & 0x7f,
    value & 0x7f,
  ]);
}
