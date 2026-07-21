import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../core/math/aabb.dart';
import 'geometry.dart';
import 'light.dart';
import 'material.dart';
import 'node.dart';

/// A renderable 3D mesh node with geometry and material.
class MeshNode extends Node {
  final Geometry geometry;
  final VRMaterial material;

  /// Global active lens distortion coefficients for the current rendering pass.
  static List<double>? activeDistortionCoefficients;

  MeshNode({super.name = 'mesh', required this.geometry, VRMaterial? material})
    : material = material ?? VRMaterial();

  @override
  Aabb get localAabb => geometry.aabb;

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    _renderTriangles(canvas, viewProjection);
  }

  void _renderTriangles(Canvas canvas, Matrix4 viewProjection) {
    final mvp = viewProjection * worldMatrix;

    // Collect projected triangles with depth for sorting
    final tris = <_ProjectedTriangle>[];

    for (var i = 0; i < geometry.indices.length; i += 3) {
      final i0 = geometry.indices[i];
      final i1 = geometry.indices[i + 1];
      final i2 = geometry.indices[i + 2];

      final v0 = _projectVertex(mvp, geometry.vertices[i0]);
      final v1 = _projectVertex(mvp, geometry.vertices[i1]);
      final v2 = _projectVertex(mvp, geometry.vertices[i2]);

      if (v0 == null || v1 == null || v2 == null) continue;

      // Backface culling
      if (!material.doubleSided) {
        final edge1 = Offset(v1.dx - v0.dx, v1.dy - v0.dy);
        final edge2 = Offset(v2.dx - v0.dx, v2.dy - v0.dy);
        final cross = edge1.dx * edge2.dy - edge1.dy * edge2.dx;
        if (cross > 0) continue; // CW winding = backface
      }

      final avgDepth = (v0.depth + v1.depth + v2.depth) / 3;

      tris.add(
        _ProjectedTriangle(
          p0: v0.offset,
          p1: v1.offset,
          p2: v2.offset,
          depth: avgDepth,
          normalIndex: i0,
        ),
      );
    }

    // Sort far to near
    tris.sort((a, b) => b.depth.compareTo(a.depth));

    // Render
    if (material.wireframe) {
      for (final tri in tris) {
        final path = Path()
          ..moveTo(tri.p0.dx, tri.p0.dy)
          ..lineTo(tri.p1.dx, tri.p1.dy)
          ..lineTo(tri.p2.dx, tri.p2.dy)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x40FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }
      return;
    }

    final positions = <Offset>[];
    for (final tri in tris) {
      positions.add(tri.p0);
      positions.add(tri.p1);
      positions.add(tri.p2);
    }

    if (positions.isNotEmpty) {
      final vertices = Vertices(VertexMode.triangles, positions);
      final paint = material.toPaint(lightFactor: 1.0);
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    }
  }

  _ProjectedVertex? _projectVertex(Matrix4 mvp, Vector3 vertex) {
    final clip = mvp.transformed3(vertex);
    // Simple perspective divide — clip.z is depth in view space
    // For Canvas rendering, we use the mvp to go directly to screen-ish coords
    final w =
        mvp.storage[3] * vertex.x +
        mvp.storage[7] * vertex.y +
        mvp.storage[11] * vertex.z +
        mvp.storage[15];
    if (w <= 0.001) return null;

    double ndcX = clip.x / w;
    double ndcY = clip.y / w;
    final ndcZ = clip.z / w;

    // Apply radial lens distortion if active
    final coeffs = activeDistortionCoefficients;
    if (coeffs != null && coeffs.isNotEmpty) {
      final rSquared = ndcX * ndcX + ndcY * ndcY;
      double rFactor = 1.0;
      double factor = 1.0;
      for (final k in coeffs) {
        rFactor *= rSquared;
        factor += k * rFactor;
      }
      ndcX *= factor;
      ndcY *= factor;
    }

    // NDC to screen will be done by the renderer setting up the canvas transform
    return _ProjectedVertex(offset: Offset(ndcX, ndcY), depth: ndcZ);
  }
}

/// Renders a mesh with per-face lighting from scene lights.
class LitMeshNode extends MeshNode {
  final List<Light> lights;

  LitMeshNode({
    super.name,
    required super.geometry,
    super.material,
    List<Light>? lights,
  }) : lights = lights ?? [];

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    _renderLitTriangles(canvas, viewProjection);
  }

  void _renderLitTriangles(Canvas canvas, Matrix4 viewProjection) {
    final mvp = viewProjection * worldMatrix;
    final modelMatrix = worldMatrix;
    final normalMatrix = Matrix4.copy(modelMatrix)
      ..invert()
      ..transpose();

    final tris = <_LitTriangle>[];

    for (var i = 0; i < geometry.indices.length; i += 3) {
      final i0 = geometry.indices[i];
      final i1 = geometry.indices[i + 1];
      final i2 = geometry.indices[i + 2];

      final v0 = _projectVertex(mvp, geometry.vertices[i0]);
      final v1 = _projectVertex(mvp, geometry.vertices[i1]);
      final v2 = _projectVertex(mvp, geometry.vertices[i2]);

      if (v0 == null || v1 == null || v2 == null) continue;

      if (!material.doubleSided) {
        final edge1 = Offset(v1.dx - v0.dx, v1.dy - v0.dy);
        final edge2 = Offset(v2.dx - v0.dx, v2.dy - v0.dy);
        if (edge1.dx * edge2.dy - edge1.dy * edge2.dx > 0) continue;
      }

      // Compute face normal in world space
      final worldNormal = normalMatrix.transformed3(geometry.normals[i0])
        ..normalize();
      final worldCenter = modelMatrix.transformed3(
        (geometry.vertices[i0] +
                geometry.vertices[i1] +
                geometry.vertices[i2]) /
            3.0,
      );

      // Accumulate light (diffuse + PBR Cook-Torrance specular highlight)
      double lightFactor = 0;
      double specularFactor = 0;
      final viewDir = (Vector3.zero() - worldCenter)..normalize();

      for (final light in lights) {
        final diffuse = light.calculateIntensity(worldCenter, worldNormal);
        lightFactor += diffuse;

        if (material.metallic > 0 || material.roughness < 0.9) {
          final lightDir = (light.transform.position - worldCenter)..normalize();
          final halfVector = (lightDir + viewDir)..normalize();
          final ndotH = max(0.0, worldNormal.dot(halfVector));
          final shininess = (1.0 - material.roughness.clamp(0.01, 1.0)) * 128.0;
          final spec = pow(ndotH, shininess).toDouble() * (0.2 + 0.8 * material.metallic);
          specularFactor += spec * diffuse;
        }
      }
      lightFactor = (lightFactor + specularFactor).clamp(0.05, 1.8);

      tris.add(
        _LitTriangle(
          p0: v0.offset,
          p1: v1.offset,
          p2: v2.offset,
          depth: (v0.depth + v1.depth + v2.depth) / 3,
          lightFactor: lightFactor,
          uv0: geometry.uvs.length > i0 ? geometry.uvs[i0] : null,
          uv1: geometry.uvs.length > i1 ? geometry.uvs[i1] : null,
          uv2: geometry.uvs.length > i2 ? geometry.uvs[i2] : null,
        ),
      );
    }

    tris.sort((a, b) => b.depth.compareTo(a.depth));

    if (material.wireframe) {
      for (final tri in tris) {
        final path = Path()
          ..moveTo(tri.p0.dx, tri.p0.dy)
          ..lineTo(tri.p1.dx, tri.p1.dy)
          ..lineTo(tri.p2.dx, tri.p2.dy)
          ..close();
        canvas.drawPath(path, material.toPaint(lightFactor: tri.lightFactor));
      }
      return;
    }

    final positions = <Offset>[];
    final colors = <Color>[];
    final textureCoords = <Offset>[];

    final hasTexture = material.map != null && material.map!.isLoaded && material.map!.image != null;
    final texWidth = hasTexture ? material.map!.width.toDouble() : 1.0;
    final texHeight = hasTexture ? material.map!.height.toDouble() : 1.0;

    final baseAlpha = (material.opacity * 255).round().clamp(0, 255);
    final baseR = (material.color.r * 255.0).round().clamp(0, 255);
    final baseG = (material.color.g * 255.0).round().clamp(0, 255);
    final baseB = (material.color.b * 255.0).round().clamp(0, 255);

    for (final tri in tris) {
      positions.add(tri.p0);
      positions.add(tri.p1);
      positions.add(tri.p2);

      if (hasTexture && tri.uv0 != null && tri.uv1 != null && tri.uv2 != null) {
        textureCoords.add(Offset(tri.uv0!.x * texWidth, tri.uv0!.y * texHeight));
        textureCoords.add(Offset(tri.uv1!.x * texWidth, tri.uv1!.y * texHeight));
        textureCoords.add(Offset(tri.uv2!.x * texWidth, tri.uv2!.y * texHeight));
      }

      final factor = tri.lightFactor;
      final r = (baseR * factor).round().clamp(0, 255);
      final g = (baseG * factor).round().clamp(0, 255);
      final b = (baseB * factor).round().clamp(0, 255);

      final litColor = Color.fromARGB(baseAlpha, r, g, b);
      colors.add(litColor);
      colors.add(litColor);
      colors.add(litColor);
    }

    if (positions.isNotEmpty) {
      final vertices = Vertices(
        VertexMode.triangles,
        positions,
        colors: colors,
        textureCoordinates: textureCoords.length == positions.length ? textureCoords : null,
      );
      final basePaint = Paint()..blendMode = material.blendMode;
      if (hasTexture) {
        basePaint.shader = ImageShader(
          material.map!.image!,
          TileMode.repeated,
          TileMode.repeated,
          Float64List.fromList(Matrix4.identity().storage),
        );
      }
      canvas.drawVertices(vertices, hasTexture ? BlendMode.modulate : BlendMode.srcOver, basePaint);
    }
  }
}

class _ProjectedVertex {
  final Offset offset;
  final double depth;
  const _ProjectedVertex({required this.offset, required this.depth});
  double get dx => offset.dx;
  double get dy => offset.dy;
}

class _ProjectedTriangle {
  final Offset p0, p1, p2;
  final double depth;
  final int normalIndex;
  const _ProjectedTriangle({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.depth,
    required this.normalIndex,
  });
}

class _LitTriangle {
  final Offset p0, p1, p2;
  final double depth;
  final double lightFactor;
  final Vector2? uv0, uv1, uv2;
  const _LitTriangle({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.depth,
    required this.lightFactor,
    this.uv0,
    this.uv1,
    this.uv2,
  });
}
