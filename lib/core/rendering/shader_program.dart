import 'dart:ui';

/// Shader uniform value types.
enum UniformType { float, vec2, vec3, vec4, mat4, texture }

/// A shader uniform variable.
class ShaderUniform {
  final String name;
  final UniformType type;
  dynamic value;

  ShaderUniform({required this.name, required this.type, this.value});
}

/// Abstraction for a shader program (vertex + fragment).
///
/// On Canvas: uses Paint shaders (limited to gradients, images).
/// On GPU (future): uses GLSL/Metal compiled shaders.
class ShaderProgram {
  final String name;
  final String? vertexSource;
  final String? fragmentSource;
  final Map<String, ShaderUniform> _uniforms = {};

  FragmentShader? _fragmentShader;

  ShaderProgram({required this.name, this.vertexSource, this.fragmentSource});

  /// Loads a fragment shader from a Flutter asset (SPIR-V or SkSL).
  Future<void> loadFromAsset(String assetPath) async {
    try {
      final program = await FragmentProgram.fromAsset(assetPath);
      _fragmentShader = program.fragmentShader();
    } catch (_) {
      // Shader not available on this platform
    }
  }

  /// Sets a uniform float value.
  void setFloat(String name, double value) {
    _uniforms[name] = ShaderUniform(
      name: name,
      type: UniformType.float,
      value: value,
    );
    _fragmentShader?.setFloat(name.hashCode % 16, value);
  }

  /// Sets a uniform vec2 value.
  void setVec2(String name, double x, double y) {
    _uniforms[name] = ShaderUniform(
      name: name,
      type: UniformType.vec2,
      value: [x, y],
    );
  }

  /// Sets a uniform vec4 value (color).
  void setColor(String name, Color color) {
    _uniforms[name] = ShaderUniform(
      name: name,
      type: UniformType.vec4,
      value: [color.r, color.g, color.b, color.a],
    );
  }

  /// Returns a Paint configured with this shader.
  Paint? toPaint() {
    if (_fragmentShader == null) return null;
    return Paint()..shader = _fragmentShader;
  }

  bool get isLoaded => _fragmentShader != null;

  void dispose() {
    _fragmentShader = null;
  }
}

/// Registry of available shader programs.
class ShaderRegistry {
  final Map<String, ShaderProgram> _shaders = {};

  /// Registers a shader program.
  void register(ShaderProgram shader) {
    _shaders[shader.name] = shader;
  }

  /// Gets a shader by name.
  ShaderProgram? get(String name) => _shaders[name];

  /// Loads all registered shaders from assets.
  Future<void> loadAll() async {
    for (final shader in _shaders.values) {
      if (!shader.isLoaded && shader.fragmentSource != null) {
        await shader.loadFromAsset(shader.fragmentSource!);
      }
    }
  }

  void dispose() {
    for (final shader in _shaders.values) {
      shader.dispose();
    }
    _shaders.clear();
  }
}
