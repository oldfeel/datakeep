import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 单文件 BT 元数据生成（对齐 market_server/torrent/create.go）。
const int torrentPieceLength = 256 * 1024;

const List<String> defaultTorrentTrackers = [
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://open.stealth.si:80/announce',
  'udp://tracker.torrent.eu.org:451/announce',
];

class TorrentCreateResult {
  const TorrentCreateResult({
    required this.magnetUrl,
    required this.torrentData,
    required this.infoHash,
    required this.displayName,
  });

  final String magnetUrl;
  final Uint8List torrentData;
  /// 40 位十六进制 info hash（大写）
  final String infoHash;
  final String displayName;
}

/// 为本机单个文件生成 .torrent 与 magnet 链接（无 WebSeed）。
Future<TorrentCreateResult> createTorrentFromFile({
  required String filePath,
  String? displayName,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw ArgumentError('文件不存在: $filePath');
  }
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw ArgumentError('仅支持单文件: $filePath');
  }
  final size = stat.size;
  if (size <= 0) {
    throw ArgumentError('空文件: $filePath');
  }

  final name = (displayName?.trim().isNotEmpty == true)
      ? displayName!.trim()
      : file.uri.pathSegments.last;
  final pieces = await _computePieceHashes(file, torrentPieceLength);

  final infoBytes = _bencodeDict({
    'length': _bencodeInt(size),
    'name': _bencodeString(name),
    'piece length': _bencodeInt(torrentPieceLength),
    'pieces': _bencodeBytes(pieces),
  });
  final infoHash = _bytesToHex(sha1.convert(infoBytes).bytes);

  final announceList = _bencodeList(
    defaultTorrentTrackers.map((t) => _bencodeList([_bencodeString(t)])).toList(),
  );
  final torrentBytes = _bencodeDict({
    'announce-list': announceList,
    'created by': _bencodeString('datakeep'),
    'info': infoBytes,
  });

  return TorrentCreateResult(
    magnetUrl: _buildMagnet(infoHash, name, defaultTorrentTrackers),
    torrentData: Uint8List.fromList(torrentBytes),
    infoHash: infoHash,
    displayName: name,
  );
}

Future<Uint8List> _computePieceHashes(File file, int pieceLen) async {
  final out = BytesBuilder(copy: false);
  final raf = await file.open();
  try {
    final buf = Uint8List(pieceLen);
    while (true) {
      final n = await raf.readInto(buf);
      if (n <= 0) break;
      final chunk = n == pieceLen ? buf : Uint8List.sublistView(buf, 0, n);
      out.add(sha1.convert(chunk).bytes);
    }
  } finally {
    await raf.close();
  }
  return out.toBytes();
}

String _buildMagnet(String infoHash, String name, List<String> trackers) {
  final buf = StringBuffer('magnet:?xt=urn:btih:$infoHash');
  buf.write('&dn=${Uri.encodeComponent(name)}');
  for (final tr in trackers) {
    buf.write('&tr=${Uri.encodeComponent(tr)}');
  }
  return buf.toString();
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString().toUpperCase();
}

List<int> _bencodeString(String s) {
  final data = utf8.encode(s);
  return [...utf8.encode('${data.length}:'), ...data];
}

List<int> _bencodeBytes(List<int> bytes) {
  return [...utf8.encode('${bytes.length}:'), ...bytes];
}

List<int> _bencodeInt(int value) => utf8.encode('i$value' 'e');

List<int> _bencodeList(List<List<int>> items) {
  final out = <int>[...utf8.encode('l')];
  for (final item in items) {
    out.addAll(item);
  }
  out.addAll(utf8.encode('e'));
  return out;
}

List<int> _bencodeDict(Map<String, List<int>> map) {
  final keys = map.keys.toList()..sort();
  final out = <int>[...utf8.encode('d')];
  for (final key in keys) {
    out.addAll(_bencodeString(key));
    out.addAll(map[key]!);
  }
  out.addAll(utf8.encode('e'));
  return out;
}
