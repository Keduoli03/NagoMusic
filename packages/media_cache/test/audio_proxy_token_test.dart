import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_cache/media_cache.dart';

/// 代理的 token 表行为。
///
/// 这里钉的是一个真实事故：整库播放（3809 首）时，队列里每首歌都会注册一个
/// token，而表的上限只有 512、且按**插入顺序**淘汰 —— 第 0 首的 token 在队列还
/// 没建完就被后面的歌挤掉了，一按播放 ExoPlayer 就拿到 404 / Source error。
void main() {
  final proxy = AudioProxyServer.instance;

  File cacheFileFor(int i) => File('${Directory.systemTemp.path}/song_$i.mp3');

  const headers = {'Authorization': 'Basic abc', 'Accept': '*/*'};

  setUp(() async {
    await proxy.resetSources();
  });

  tearDownAll(() async {
    await proxy.resetSources();
  });

  test('同一首歌重复注册拿回同一个 token', () async {
    final first = await proxy.registerSource(
      uri: Uri.parse('https://example.com/a.mp3'),
      headers: headers,
      cacheFile: cacheFileFor(1),
    );
    final second = await proxy.registerSource(
      uri: Uri.parse('https://example.com/a.mp3'),
      headers: headers,
      cacheFile: cacheFileFor(1),
    );

    expect(
      first.queryParameters['token'],
      second.queryParameters['token'],
      reason: '预热 / TTL 重注册 / 出错重试都会重复注册，每次换 token 会把表冲掉',
    );
  });

  test('不同歌拿到不同 token', () async {
    final a = await proxy.registerSource(
      uri: Uri.parse('https://example.com/a.mp3'),
      headers: headers,
      cacheFile: cacheFileFor(1),
    );
    final b = await proxy.registerSource(
      uri: Uri.parse('https://example.com/b.mp3'),
      headers: headers,
      cacheFile: cacheFileFor(2),
    );
    expect(a.queryParameters['token'], isNot(b.queryParameters['token']));
  });

  test('鉴权头不同视为不同源', () async {
    final a = await proxy.registerSource(
      uri: Uri.parse('https://example.com/a.mp3'),
      headers: const {'Authorization': 'Basic aaa'},
      cacheFile: cacheFileFor(1),
    );
    final b = await proxy.registerSource(
      uri: Uri.parse('https://example.com/a.mp3'),
      headers: const {'Authorization': 'Basic bbb'},
      cacheFile: cacheFileFor(1),
    );
    expect(a.queryParameters['token'], isNot(b.queryParameters['token']));
  });

  test('整库长度的队列不会把开头几首挤掉', () async {
    // 用户真实队列是 3809 首；旧上限 512 时第 0 首必然被淘汰。
    const queueLength = 3809;
    final tokens = <String>[];
    for (var i = 0; i < queueLength; i++) {
      final uri = await proxy.registerSource(
        uri: Uri.parse('https://example.com/song$i.mp3'),
        headers: headers,
        cacheFile: cacheFileFor(i),
      );
      tokens.add(uri.queryParameters['token']!);
    }

    // 队列里的每一个 token 都必须还在 —— 整条队列的地址已经交给 ExoPlayer 了，
    // 少一个就是播到那首时 404。
    expect(proxy.hasToken(tokens.first), isTrue, reason: '正在播的第一首被淘汰了');
    expect(proxy.hasToken(tokens[queueLength ~/ 2]), isTrue);
    expect(proxy.hasToken(tokens.last), isTrue);
  });
}
