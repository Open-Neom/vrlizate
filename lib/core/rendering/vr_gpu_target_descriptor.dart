/// GPU backend types supported for external render target presentation.
enum VrGpuBackend {
  openGlEs,
  vulkan,
  metal,
  mock,
}

/// Common texture pixel formats used by VR swapchains and render targets.
enum VrGpuTextureFormat {
  rgba8,
  srgb8Alpha8,
  rgb10a2,
  rgba16f,
  depth24Stencil8,
  depth32f,
}

/// Immutable descriptor defining the properties of an external GPU render target.
class VrExternalRenderTargetDescriptor {
  final VrGpuBackend backend;
  final VrGpuTextureFormat format;
  final int width;
  final int height;
  final int sampleCount;
  final bool isArrayTexture;
  final int arrayLayers;

  const VrExternalRenderTargetDescriptor({
    required this.backend,
    required this.format,
    required this.width,
    required this.height,
    this.sampleCount = 1,
    this.isArrayTexture = false,
    this.arrayLayers = 1,
  })  : assert(width > 0, 'Width must be positive'),
        assert(height > 0, 'Height must be positive'),
        assert(sampleCount >= 1, 'Sample count must be at least 1'),
        assert(arrayLayers >= 1, 'Array layers must be at least 1');

  double get aspectRatio => width / height;

  Map<String, Object?> toJson() => <String, Object?>{
        'backend': backend.name,
        'format': format.name,
        'width': width,
        'height': height,
        'sampleCount': sampleCount,
        'isArrayTexture': isArrayTexture,
        'arrayLayers': arrayLayers,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrExternalRenderTargetDescriptor &&
          backend == other.backend &&
          format == other.format &&
          width == other.width &&
          height == other.height &&
          sampleCount == other.sampleCount &&
          isArrayTexture == other.isArrayTexture &&
          arrayLayers == other.arrayLayers;

  @override
  int get hashCode => Object.hash(
        backend,
        format,
        width,
        height,
        sampleCount,
        isArrayTexture,
        arrayLayers,
      );

  @override
  String toString() =>
      'VrExternalRenderTargetDescriptor(${backend.name}, ${format.name}, '
      '${width}x$height, samples: $sampleCount, layers: $arrayLayers)';
}
