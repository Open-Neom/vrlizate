/// GPU rendering abstraction layer.
///
/// Provides an interface for future GPU-accelerated rendering
/// via flutter_gpu / Impeller when it becomes stable.
/// Currently serves as documentation of the target API.
///
/// When flutter_gpu matures, implement [GPURenderer] with:
/// - gpu.RenderTarget for off-screen rendering
/// - gpu.CommandBuffer for batched draw calls
/// - gpu.Shader for custom GLSL/Metal shaders
/// - gpu.HostBuffer for vertex/index data upload
///
/// This allows vrlizate to seamlessly upgrade from Canvas
/// to GPU rendering without changing the scene graph API.
abstract class GPURenderer {
  /// Whether GPU rendering is available on this platform.
  bool get isAvailable;

  /// Initializes the GPU context.
  Future<void> initialize();

  /// Begins a new render frame.
  void beginFrame(double width, double height);

  /// Ends the frame and returns the rendered image.
  Future<dynamic> endFrame();

  /// Binds a vertex buffer for rendering.
  void bindVertexBuffer(List<double> vertices, List<int> indices);

  /// Binds a shader program.
  void bindShader(String vertexShader, String fragmentShader);

  /// Sets a uniform value.
  void setUniform(String name, dynamic value);

  /// Draws the currently bound geometry.
  void draw();

  /// Releases GPU resources.
  void dispose();
}

/// Stub implementation that reports GPU is not available.
/// Replace with real implementation when flutter_gpu is stable.
class GPURendererStub implements GPURenderer {
  @override
  bool get isAvailable => false;

  @override
  Future<void> initialize() async {}

  @override
  void beginFrame(double width, double height) {}

  @override
  Future<dynamic> endFrame() async => null;

  @override
  void bindVertexBuffer(List<double> vertices, List<int> indices) {}

  @override
  void bindShader(String vertexShader, String fragmentShader) {}

  @override
  void setUniform(String name, dynamic value) {}

  @override
  void draw() {}

  @override
  void dispose() {}
}
