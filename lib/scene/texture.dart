import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Texture for mapping images onto mesh surfaces.
class VRTexture {
  final String name;
  ui.Image? _image;
  int _width = 0;
  int _height = 0;
  bool _loaded = false;

  TextureWrap wrapS;
  TextureWrap wrapT;
  TextureFilter filter;

  VRTexture({
    this.name = 'texture',
    this.wrapS = TextureWrap.repeat,
    this.wrapT = TextureWrap.repeat,
    this.filter = TextureFilter.linear,
  });

  bool get isLoaded => _loaded;
  ui.Image? get image => _image;
  int get width => _width;
  int get height => _height;

  /// Loads texture from asset path.
  Future<void> loadAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _image = frame.image;
    _width = _image!.width;
    _height = _image!.height;
    _loaded = true;
  }

  /// Creates texture from raw RGBA bytes.
  Future<void> fromBytes(Uint8List rgba, int width, int height) async {
    final completer = ui.ImmutableBuffer.fromUint8List(rgba);
    final buffer = await completer;
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    _image = frame.image;
    _width = width;
    _height = height;
    _loaded = true;
  }

  /// Creates a 1x1 solid color texture.
  Future<void> fromColor(ui.Color color) async {
    final bytes = Uint8List.fromList([
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
      (color.a * 255.0).round().clamp(0, 255),
    ]);
    await fromBytes(bytes, 1, 1);
  }

  /// Samples UV coordinate (0-1) and returns approximate color.
  ui.Color sample(double u, double v) {
    if (!_loaded || _image == null) return const ui.Color(0xFFFF00FF);
    // Wrap UVs
    u = _wrapCoord(u, wrapS);
    v = _wrapCoord(v, wrapT);
    return const ui.Color(
      0xFFCCCCCC,
    ); // Placeholder — real sampling requires pixel access
  }

  double _wrapCoord(double coord, TextureWrap wrap) {
    return switch (wrap) {
      TextureWrap.repeat => coord % 1.0,
      TextureWrap.clamp => coord.clamp(0, 1),
      TextureWrap.mirror =>
        ((coord.floor() % 2 == 0) ? coord % 1.0 : 1.0 - (coord % 1.0)),
    };
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _loaded = false;
  }
}

enum TextureWrap { repeat, clamp, mirror }

enum TextureFilter { nearest, linear }
