import 'dart:convert';
import 'dart:typed_data';

class CuppsFrameCodec {
  const CuppsFrameCodec();

  static const protocolVersion = '0100';
  static const headerLength = 10;

  Uint8List encode(String xml) {
    final payload = utf8.encode(xml);
    final length = payload.length.toRadixString(16).padLeft(6, '0');
    final header = ascii.encode('$protocolVersion$length');
    return Uint8List.fromList([...header, ...payload]);
  }

  CuppsFrameDecodeResult decode(List<int> bytes) {
    final decoder = CuppsFrameDecoder();
    decoder.add(bytes);
    return CuppsFrameDecodeResult(
      frames: decoder.takeFrames(),
      remainingBytes: decoder.bufferedBytes,
    );
  }
}

class CuppsFrameDecodeResult {
  const CuppsFrameDecodeResult({
    required this.frames,
    required this.remainingBytes,
  });

  final List<String> frames;
  final int remainingBytes;
}

class CuppsFrameDecoder {
  final _buffer = <int>[];
  final _frames = <String>[];

  int get bufferedBytes => _buffer.length;

  void add(List<int> chunk) {
    _buffer.addAll(chunk);
    _drain();
  }

  List<String> takeFrames() {
    final frames = List<String>.of(_frames);
    _frames.clear();
    return frames;
  }

  void reset() {
    _buffer.clear();
    _frames.clear();
  }

  void _drain() {
    while (_buffer.isNotEmpty) {
      final headerStart = _findHeaderStart();
      if (headerStart == -1) {
        _keepPossibleHeaderPrefix();
        return;
      }

      if (headerStart > 0) {
        _buffer.removeRange(0, headerStart);
      }

      if (_buffer.length < CuppsFrameCodec.headerLength) return;

      final header = ascii.decode(
        _buffer.take(CuppsFrameCodec.headerLength).toList(),
        allowInvalid: true,
      );
      final lengthHex = header.substring(4);
      final payloadLength = int.tryParse(lengthHex, radix: 16);
      if (!header.startsWith(CuppsFrameCodec.protocolVersion) ||
          payloadLength == null) {
        _buffer.removeAt(0);
        continue;
      }

      final fullLength = CuppsFrameCodec.headerLength + payloadLength;
      if (_buffer.length < fullLength) return;

      final payload = _buffer
          .skip(CuppsFrameCodec.headerLength)
          .take(payloadLength)
          .toList();
      _frames.add(utf8.decode(payload));
      _buffer.removeRange(0, fullLength);
    }
  }

  int _findHeaderStart() {
    final pattern = ascii.encode(CuppsFrameCodec.protocolVersion);
    for (var i = 0; i <= _buffer.length - pattern.length; i++) {
      var matches = true;
      for (var j = 0; j < pattern.length; j++) {
        if (_buffer[i + j] != pattern[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return i;
    }
    return -1;
  }

  void _keepPossibleHeaderPrefix() {
    final text = ascii.decode(_buffer, allowInvalid: true);
    for (
      var length = CuppsFrameCodec.protocolVersion.length - 1;
      length > 0;
      length--
    ) {
      final suffix = text.substring(text.length - length);
      if (CuppsFrameCodec.protocolVersion.startsWith(suffix)) {
        final keep = _buffer.sublist(_buffer.length - length);
        _buffer
          ..clear()
          ..addAll(keep);
        return;
      }
    }
    _buffer.clear();
  }
}
