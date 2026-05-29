import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/services/navidrome/navidrome_source_repository.dart';

void main() {
  test('builds token based Subsonic API URLs under endpoint path', () {
    final repo = NavidromeSourceRepository.instance;
    const source = NavidromeSource(
      id: 'navidrome-1',
      name: 'Home',
      endpoint: 'https://music.example.com/navidrome/',
      username: 'alice',
      password: 'secret',
      salt: 'abc123',
    );

    final uri = repo.apiUri(source, 'stream', query: {'id': 'song-1'});

    expect(uri.toString(), contains('/navidrome/rest/stream.view'));
    expect(uri.queryParameters['u'], 'alice');
    expect(uri.queryParameters['s'], 'abc123');
    expect(uri.queryParameters['v'], NavidromeSourceRepository.apiVersion);
    expect(uri.queryParameters['c'], NavidromeSourceRepository.clientName);
    expect(uri.queryParameters['f'], 'json');
    expect(uri.queryParameters['id'], 'song-1');
    expect(uri.queryParameters['t'], isNotEmpty);
    expect(uri.queryParameters.containsKey('p'), isFalse);
  });

  test('accepts endpoints that already include rest path', () {
    final repo = NavidromeSourceRepository.instance;
    const source = NavidromeSource(
      id: 'navidrome-1',
      name: 'Home',
      endpoint: 'https://music.example.com/rest',
      username: 'alice',
      password: 'secret',
      salt: 'abc123',
    );

    final uri = repo.apiUri(source, 'ping');

    expect(uri.path, '/rest/ping.view');
  });
}
