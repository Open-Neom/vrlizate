<p align="center">
  <img src="doc/logo.png" alt="VRlizate" width="600"/>
</p>

# VRlizate

**Español** · [English](#english)

VRlizate es un motor 3D/VR Open Source escrito en Dart para crear experiencias
inmersivas accesibles desde smartphones y aplicaciones Flutter. El paquete
`vrlizate` está en la versión **1.11.0**; el objetivo del ecosistema abierto es
ofrecer un núcleo verificable y extensible: un mismo
formato de escenas e interacción que pueda adaptarse desde teléfonos económicos
hasta dispositivos con seguimiento avanzado.

> Estado: desarrollo activo. La disponibilidad de sensores y el rendimiento se
> verifican por dispositivo; las funciones opcionales requieren integración de
> la aplicación anfitriona.

## Qué incluye 1.11.0

- Escenas 3D con perfiles Lite/Standard/High y consultas de sombras acotadas.
- Protocolo padre/hijo, transporte TCP local autenticado y controlador IMU 3DoF.
- Avatar del teléfono con distribución de botones y modelo de brazo estimado.
- Flecha de regreso 3D, mejoras al Home de ejemplo y reinicio correcto del dwell
  después de suprimirlo por otra entrada.

```yaml
dependencies:
  vrlizate: ^1.11.0
```

Este paquete contiene el núcleo y el renderer Dart/Canvas. La clase
`VrlizateScene` pertenece a ese núcleo; el paquete independiente
`vrlizate_scene` aporta el adaptador Flutter GPU. Los widgets para ese adaptador
se distribuyen por separado en `vrlizate_widgets`.

## Principios

- **Accesible:** el nivel Lite prioriza 3DoF, gaze y dispositivos modestos.
- **Progresivo:** una experiencia puede añadir controles, iluminación y 6DoF
  cuando el hardware los soporte.
- **Extensible:** sensores y controles comunitarios implementan
  `VrInputDriver` sin acoplarse a una escena.
- **Predecible:** el árbitro reutiliza eventos mediante un pool de capacidad
  fija. Esto no elimina las asignaciones del renderer, JSON o snapshots de red.
- **Abierto:** código Apache 2.0, decisiones documentadas y contribuciones
  verificadas por tests.

Consulta [ARCHITECTURE.md](ARCHITECTURE.md) para ver los niveles Lite, Standard
y Pro, así como el flujo completo entre sensores, interacción y renderizado.

## Requisitos

- Flutter compatible con Dart `>=3.10.8 <4.0.0`.
- Un dispositivo, simulador o plataforma de escritorio soportada por Flutter.
- Giroscopio para seguimiento de cabeza en un teléfono físico. Escritorio y web
  pueden utilizar sus entradas de respaldo.

## Clonar y verificar

```bash
git clone https://github.com/Open-Neom/vrlizate.git
cd vrlizate
flutter pub get
flutter test
flutter analyze
```

Para ejecutar la aplicación de demostración:

```bash
cd example
flutter pub get
flutter run
```

Usa `flutter devices` para seleccionar explícitamente un teléfono o una
plataforma de escritorio.

## Crear una experiencia mínima

Añade el paquete a tu `pubspec.yaml` y construye una escena con la API pública:

```dart
import 'dart:ui';

import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

final engine = VREngine(
  scene: VrlizateScene(
    quality: VrlizateSceneQuality.standard,
    rayTracingMode: VrlizateRayTracingMode.hybridObjectSpace,
  ),
);

void createExperience() {
  engine.cameraRig.position = Vector3(0, 1.6, 3);
  engine.scene.add(
    LitMeshNode(
      name: 'welcome-cube',
      geometry: CubeGeometry(size: 1),
      material: PBRMaterial(color: const Color(0xFF2E90FA)),
    ),
  );
  engine.enableHeadTracking();
  engine.enableGazePointer(dwellDuration: 1.5);
  engine.start();
}
```

La carpeta [`example/`](example/) contiene escenas más completas. Mantén la
lógica particular de tu experiencia fuera del núcleo y compón módulos mediante
las API públicas de escena, interacción, locomoción y entrada.

### Calidad 3D y trazado de rayos móvil

`VrlizateScene` es la escena moderna recomendada. Conserva meshes reales,
materiales PBR, luces, niebla, UI espacial y culling. No debe confundirse con
la clase histórica `VRScene`, mantenida por compatibilidad con experiencias de
partículas 2D.

Los perfiles ajustan automáticamente la teselación y el máximo de consultas de
luz: `lite` desactiva las consultas, `standard` admite 18 y `high` 36 por frame.
El límite se puede sobrescribir después de medir el dispositivo. El modo
`hybridObjectSpace` sigue rasterizando los triángulos y lanza rayos CPU contra
AABB de los objetos más cercanos para estimar oclusión de luz directa. Produce
sombras espaciales estables en estéreo con un costo acotado, pero no ofrece
reflejos ni iluminación global de un path tracer por píxel.

En el demo, arrastra para mirar, camina en el sitio para acercarte a los paneles
y toca o usa dwell para abrirlos. Doble toque recentra la vista. El Home, su
barra inferior y las flechas de regreso viven dentro del mismo mundo 3D.

## Crear un driver de entrada

`VrInputArbiter` aplica la prioridad `remotePhone/touch > periféricos > gaze`.
Una interacción aceptada se entrega síncronamente; un dwell de gaze queda
suprimido durante 400 ms después de la última actividad de mayor prioridad.
Cuando la aplicación gestiona `GazePointer` directamente, debe pasar
`dwellEnabled: !arbiter.isGazeSuppressed` a `update`. Así, al terminar la
supresión, el usuario dispone de un intervalo completo para seleccionar.

```dart
final class CommunityGamepadDriver implements VrInputDriver {
  VrInputSink? _sink;
  final Map<String, dynamic> _axisPayload = <String, dynamic>{
    'x': 0.0,
    'y': 0.0,
  };

  @override
  VrInputSource get source => VrInputSource.gamepad;

  @override
  void attach(VrInputSink sink) {
    _sink = sink;
    // Suscríbete aquí a la API del gamepad.
  }

  void onAxis(double x, double y) {
    final sink = _sink;
    if (sink == null) return;

    _axisPayload['x'] = x;
    _axisPayload['y'] = y;
    final event = sink.acquire(
      type: VrInputType.navigate,
      data: _axisPayload,
      active: x.abs() > 0.1 || y.abs() > 0.1,
    );
    try {
      sink.submit(event);
    } finally {
      sink.release(event);
    }
  }

  @override
  void detach() {
    // Cancela aquí las suscripciones nativas.
    _sink = null;
  }
}

final arbiter = VrInputArbiter();
final gamepad = CommunityGamepadDriver();

arbiter.addListener((event) {
  // El evento es memoria prestada: úsalo solo dentro de este callback.
});
arbiter.attachDriver(gamepad);
```

No conserves una referencia a un evento después del callback. Si necesitas
historial, copia solamente los valores requeridos. Reutiliza también el payload
del driver cuando este se emita cada frame.

## Usar un segundo teléfono como control 3DoF

El visor puede abrir un socket local autenticado y compartir la URI resultante
como QR. La aplicación anfitriona debe obtener la IP LAN que el otro teléfono
pueda alcanzar; `0.0.0.0` sirve para enlazar el servidor, no para anunciarlo.

```dart
import 'dart:convert';
import 'dart:math';

final random = Random.secure();
final oneTimeRandomToken = base64UrlEncode(
  List<int>.generate(24, (_) => random.nextInt(256)),
);
final transport = VrLocalSocketTransport();
final invitation = await transport.listen(
  bindHost: '0.0.0.0',
  advertisedHost: '192.168.1.20',
  sessionToken: oneTimeRandomToken,
);

final arbiter = VrInputArbiter();
final session = VrRemoteControllerSession(
  transport: transport,
  arbiter: arbiter,
  cameraRig: engine.cameraRig,
  scene: engine.scene,
)..start();

// Codifica invitation.toUri() como QR en la capa de aplicación.
```

El teléfono controlador abre la URI y transmite su perfil e IMU:

```dart
final transport = VrLocalSocketTransport();
await transport.connect(VrPairingPayload.fromUri(scannedUri));

final controller = VrRemoteImuController(
  transport: transport,
  profile: VrControllerProfile(
    deviceId: 'my-phone',
    deviceName: 'Control derecho',
    handedness: VrControllerHandedness.right,
    widthMeters: 0.072,
    heightMeters: 0.155,
    controls: [
      VrControlDescriptor(
        id: 'select',
        label: 'A',
        kind: VrControlKind.button,
        x: 0.75,
        y: 0.75,
      ),
    ],
  ),
);
await controller.start();
```

`VrRemoteControllerSession` crea un teléfono 3D, ilumina los controles mediante
un bitset y usa `VrControllerArmModel` para estimar una posición cómoda relativa
a la cabeza. La rotación sí proviene del giroscopio; la posición visual es una
estimación acotada, no seguimiento 6DoF medido. El acelerómetro se transmite
pero nunca se integra como posición. Una distancia opcional debe incluir fuente
y confianza. El perfil describe los botones; la aplicación del control aporta
su interfaz táctil y configura la orientación de pantalla.
`VrRemoteImuController` se suscribe a `sensors_plus` y también admite streams
de sensores inyectados para pruebas o integraciones alternativas.

El socket de referencia funciona en plataformas `dart:io` y está pensado para
una LAN confiable. Autentica el token de sesión, pero no cifra el tráfico. Una
aplicación que atraviese redes no confiables debe proporcionar un transporte
seguro alternativo. El codec de referencia usa JSON, con snapshots que poseen
su memoria antes de una operación asíncrona. BLE y Wi-Fi Direct todavía
requieren implementar otro transporte; la ruta TCP no está disponible en web.

Para mantener la predicción actualizada entre paquetes, llama a
`session.updatePosePrediction()` antes de renderizar. En el cierre, detén la
sesión y libera sus recursos junto con el transporte y los sensores.

## Módulos principales

```text
lib/
├── core/          Cámara, motor, entrada, matemáticas, proyección y render
├── scene/         Grafo de escena, geometrías, materiales, luces y texturas
├── interaction/   Raycast, objetos interactivos y locomoción
├── spatial_ui/    Paneles, texto y botones espaciales
├── animation/     Clips, esqueletos, keyframes y skinning
├── physics/       Cuerpos rígidos y colisiones
├── effects/       Distorsión, niebla, bloom, SSAO y viñeta
├── loaders/       Carga de glTF/GLB
└── xr/            Integraciones XR
```

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir un cambio. Todo cambio de
comportamiento debe incluir tests; las rutas ejecutadas cada frame deben evitar
asignaciones accidentales y documentar sus límites de hardware.

## Licencia

Apache License 2.0. Consulta [LICENSE](LICENSE).

---

## English

VRlizate is an open-source 3D/VR engine written in Dart for immersive
experiences on smartphones and Flutter applications. The `vrlizate` package is
at **1.11.0**. Its goal is a testable, extensible core: one scene and interaction model that scales from
low-end phones to devices with advanced tracking.

> Status: active development. Sensor availability and performance must be
> checked on each device; optional capabilities need host-app integration.

Version 1.11.0 adds the parent/child controller protocol and local TCP transport,
an estimated arm model and phone avatar, spatial back navigation, bounded hybrid
light queries, and corrected gaze dwell suppression. Add `vrlizate: ^1.11.0` to
your dependencies and see [CHANGELOG.md](CHANGELOG.md) for the release notes.

This package uses the Dart/Canvas renderer. Its `VrlizateScene` class is distinct
from the separate `vrlizate_scene` Flutter GPU adapter package and that adapter's
`vrlizate_widgets` components.

## Principles

- **Accessible:** Lite prioritizes 3DoF, gaze, and modest devices.
- **Progressive:** experiences can add controllers, lighting, and 6DoF when the
  hardware supports them.
- **Extensible:** community sensors and controllers implement `VrInputDriver`
  without coupling themselves to a scene.
- **Predictable:** the arbiter reuses fixed-pool events; JSON, network snapshots,
  and rendering still allocate memory.
- **Open:** Apache 2.0 code, documented decisions, and test-backed changes.

Read [ARCHITECTURE.md](ARCHITECTURE.md) for the Lite, Standard, and Pro tiers
and the complete sensor-to-rendering data flow.

## Requirements and verification

- Flutter with Dart `>=3.10.8 <4.0.0`.
- A Flutter-supported device, simulator, or desktop platform.
- A gyroscope for head tracking on a physical phone.

```bash
git clone https://github.com/Open-Neom/vrlizate.git
cd vrlizate
flutter pub get
flutter test
flutter analyze
```

Run the example application with:

```bash
cd example
flutter pub get
flutter run
```

The minimal scene and driver examples in the Spanish sections above use the
same language-independent Dart API. Experience-specific logic should live
outside the engine and compose the public scene, interaction, locomotion, and
input modules.

### 3D quality and mobile ray tracing

Use `VrlizateScene` for modern experiences. It provides mesh geometry, PBR
materials, lighting, fog, spatial UI, culling, and hardware-aware quality
profiles. The legacy `VRScene` remains only for compatibility with the older
2D particle-style API.

`hybridObjectSpace` keeps triangle rasterization and spends a bounded CPU ray
budget on direct-light visibility against world AABBs. Defaults are zero rays
for `lite`, 18 for `standard`, and 36 for `high`; applications may override the
budget after profiling. This gives stable stereo object shadows without
claiming per-pixel path tracing, global illumination, or ray-traced reflections.

## Adding an input driver

Implement `VrInputDriver`, keep the `VrInputSink` received by `attach`, and
cancel every hardware subscription in `detach`. For high-frequency values:

1. Reuse payload storage.
2. Call `sink.acquire`.
3. Call `sink.submit` inside a `try` block.
4. Always call `sink.release` in `finally`.
5. Never retain an event delivered to an arbiter listener.

## Second-phone 3DoF controller

`VrLocalSocketTransport` provides the native `dart:io` reference transport.
The visor calls `listen`, shares the resulting pairing URI, and connects a
`VrRemoteControllerSession` to its arbiter, camera, and scene. The child calls
`connect` and starts `VrRemoteImuController` with a `VrControllerProfile`.

The profile describes normalized visual control locations. Pose frames carry a
normalized quaternion, angular velocity, acceleration, button bitset, optional
touch, sequence number, and optional range with source/confidence. The Lite
avatar uses a bounded arm model to estimate a comfortable head-relative
position, not measured 6DoF tracking. Acceleration is never integrated into
translation. The host app provides the controller UI and screen-axis settings;
`VrRemoteImuController` subscribes to `sensors_plus` or injected sensor streams. The
reference socket authenticates but does not encrypt LAN traffic; untrusted
networks need a secure transport. The codec uses JSON and owned snapshots;
BLE/Wi-Fi Direct need separate implementations and TCP is unavailable on web.

Call `session.updatePosePrediction()` before rendering to refresh prediction
between packets, and dispose the session, transport, and sensors on exit.

`VrInputArbiter` enforces `remotePhone/touch > peripherals > gaze`. A gaze dwell
is suppressed for 400 ms after the last active higher-priority event, while
gaze hover remains available for reticle feedback.
Applications updating `GazePointer` themselves must pass
`dwellEnabled: !arbiter.isGazeSuppressed` to `update` so suppression clears the
timer and a full dwell interval is required when it ends.

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Behavioral
changes require tests, and per-frame paths must avoid accidental allocations.
VRlizate is licensed under [Apache License 2.0](LICENSE).
