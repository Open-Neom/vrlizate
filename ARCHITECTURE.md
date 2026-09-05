# Arquitectura de VRlizate / VRlizate Architecture

**Español** · [English](#english)

## Objetivo

VRlizate utiliza un núcleo común y capacidades progresivas. Lite, Standard y
Pro no son motores separados: son niveles de ejecución de la misma experiencia.
El código debe consultar capacidades y degradarse de forma explícita en lugar de
suponer que todos los teléfonos tienen el mismo rendimiento o sensores.

## Niveles de hardware

| Nivel | Hardware esperado | Entrada | Renderizado recomendado |
|---|---|---|---|
| **Lite** | Smartphone económico, visor pasivo, seguimiento 3DoF | Gaze, touch, temple tap | Geometría simple, materiales básicos, iluminación limitada y efectos opcionales desactivados |
| **Standard** | Smartphone intermedio y control externo o segundo teléfono | Lite + gamepad, mando remoto, manos opcionales | Iluminación intermedia, texturas y mayor densidad de escena con presupuesto medido |
| **Pro** | Hardware con cámaras y sensores avanzados | 6DoF, seguimiento de manos y periféricos espaciales | Seguimiento avanzado, escenas más densas y efectos habilitados según mediciones térmicas |

Una experiencia debe conservar su función principal en Lite. Standard y Pro
añaden fidelidad o métodos de interacción, pero no deberían ser necesarios para
completar una acción esencial salvo que el módulo declare explícitamente otro
requisito.

## Flujo de datos

```text
Sensores físicos / red / cámara / touch
                  │
                  ▼
       VrInputDriver de cada fuente
                  │ acquire / submit / release
                  ▼
          Pool fijo de VrInputEvent
                  │ memoria prestada
                  ▼
             VrInputArbiter
        prioridad + supresión + 400 ms
                  │ callback síncrono
                  ▼
       Acciones de interacción/locomoción
                  │ actualizan estado
                  ▼
       Scene Graph + CameraRig + Physics
                  │ frame actual
                  ▼
          RenderPass / VRRenderer
                  │
                  ▼
          Vista mono o estereoscópica
```

El seguimiento de cabeza actualiza `CameraRig`. Las entradas orientadas a una
acción pasan por el árbitro antes de modificar la experiencia. El renderizador
lee el estado resultante; no debe consultar directamente hardware de entrada.
Esta separación permite reemplazar un gamepad, un segundo teléfono o un driver
de visión sin modificar una escena.

## Arbitraje multimodal

La jerarquía estable es:

1. **Máxima:** `remotePhone` y `touch`.
2. **Media:** `templeTap`, `gamepad`, voz, sonar, manos y periféricos externos.
3. **Base:** `gaze`.

Un evento activo registra actividad en su nivel. Durante la ventana configurable
de 400 ms, los eventos accionables de niveles inferiores se descartan. El hover
de gaze continúa para mantener visible el retículo, pero su `select` automático
por dwell se suprime. Al terminar la ventana, gaze vuelve a funcionar sin una
transición especial.

## Contrato Zero-GC

`VrInputEventPool` crea todas sus instancias al iniciar. En el camino caliente:

```text
acquire → rellenar/reutilizar payload → submit → callback síncrono → release
```

- El pool tiene capacidad fija y falla de forma visible si se agota; no crea un
  objeto de emergencia.
- `release` elimina referencias a `targetId` y `data` para no retener memoria.
- Un evento no puede liberarse dos veces ni devolverse a otro pool.
- `assertNoLeaks()` permite verificar que todos los eventos regresaron.
- Los listeners no pueden conservar el objeto. Quien necesite persistencia copia
  únicamente los valores necesarios.
- El pool elimina asignaciones de eventos, no asignaciones creadas por un driver
  dentro de su payload. Un driver de 60–120 Hz debe reutilizar también ese estado.

El `VrInputEventBus` basado en streams se conserva como API compatible para
flujos asíncronos de baja frecuencia. El árbitro síncrono es la ruta recomendada
para joystick, hover y sensores por frame.

## Límites entre módulos

- `core/input`: traduce hardware a eventos canónicos; no conoce escenas.
- `interaction`: convierte eventos aceptados en selección, agarre o locomoción.
- `scene`: conserva estado espacial y jerarquía; no abre sensores.
- `core/rendering`: dibuja un snapshot del estado; no decide intención.
- `effects`: son opcionales y deben poder desactivarse por nivel de hardware.
- `example`: demuestra integración, pero no define contratos del núcleo.

Un módulo nuevo debe depender hacia el núcleo, no desde el núcleo hacia una
experiencia concreta.

## Extender el motor

Para añadir un método de entrada:

1. Implementa `VrInputDriver` y selecciona el `VrInputSource` más específico.
2. Suscríbete al hardware en `attach` y cancela todo en `detach`.
3. Reutiliza buffers y payloads para datos de alta frecuencia.
4. Emite tipos canónicos (`select`, `navigate`, `hover`, etc.).
5. Añade tests de prioridad, liberación y comportamiento al desconectar.
6. Documenta sensores, permisos, frecuencia y nivel mínimo de hardware.

Para añadir renderizado o efectos, define primero el comportamiento Lite y haz
que las mejoras Standard/Pro sean opt-in y medibles.

## Escena 3D moderna y trazado híbrido

Las experiencias nuevas deben construir `VREngine` con `VrlizateScene`. Esta
clase amplía el grafo `Scene` que usa `MeshNode`, `LitMeshNode`, materiales PBR,
luces y UI espacial. La clase histórica `VRScene` representa una colección de
elementos 2D y se conserva únicamente por compatibilidad; no es la base del
Home ni de los demos de alta calidad.

```text
VrlizateScene.update
        │ actualiza matrices y AABB en caché
        ▼
RenderPass: culling + orden por profundidad + luces
        │
        ├─ rasterización de meshes y UI en cada ojo
        │
        └─ HybridRayTracer (presupuesto fijo, una vez por frame)
             │ rayos hacia la luz primaria
             ▼
        visibilidad directa por LitMeshNode
```

El trazado híbrido es deliberadamente de espacio de objetos: intersecta rayos
con AABB mundiales y modula la luz directa del objeto receptor. No recorre cada
píxel ni calcula rebotes, iluminación global o reflejos. Se ejecuta una sola vez
por revisión de escena para que el ojo izquierdo y el derecho compartan el
resultado y no dupliquen el costo.

| Perfil de escena | Segmentos de esfera | Rayos máximos por frame | Uso recomendado |
|---|---:|---:|---|
| `lite` | 10 | 0 | Teléfonos económicos y control térmico estricto |
| `standard` | 16 | 18 | Calidad equilibrada para smartphones intermedios |
| `high` | 24 | 36 | Dispositivos medidos con margen térmico |

Estos son límites, no objetivos obligatorios. `RenderPass` prioriza receptores
cercanos a la cámara y conserva luz ambiente para que una sombra no vuelva
ilegible la escena. Una evolución hacia ray tracing por triángulo o por píxel
requiere BVH, cómputo GPU y perfiles térmicos separados; no debe reemplazar la
ruta Lite.

## Controlador remoto padre/hijo

El flujo de referencia para dos teléfonos es:

```text
Hijo: IMU + pantalla              Padre: visor + render
        │                                 ▲
VrRemoteImuController                     │
        │ profile / pose / input          │
        ▼                                 │
VrControllerTransport ───────── VrRemoteControllerSession
                                          ├─ VrLaserPointerDriver
                                          ├─ VrInputArbiter
                                          ├─ ControllerState
                                          └─ VrControllerAvatarNode
```

- `VrPairingPayload` es una invitación, no un mecanismo de descubrimiento.
- `VrLocalSocketTransport` ofrece el transporte LAN de referencia y valida el
  token antes de aceptar perfil, pose o entrada.
- Los eventos prestados del pool se copian síncronamente a un snapshot antes de
  cualquier operación asíncrona de red.
- Los frames tienen secuencia; el padre descarta frames repetidos o atrasados.
- El avatar Lite usa posición relativa fija. Una distancia de BLE/RTT/UWB o
  visión es metadato con confianza y no convierte por sí sola el sistema en 6DoF.
- El acelerómetro se conserva como señal de movimiento; integrarlo dos veces
  para calcular posición no está permitido en la ruta Lite.
- TCP local autentica pero no cifra. BLE, Wi-Fi Direct, WebRTC o TLS pueden
  implementar el mismo contrato cuando el entorno requiera otra seguridad.

---

## English

## Goal

VRlizate has one core with progressive capabilities. Lite, Standard, and Pro
are execution tiers of the same experience, not separate engines. Code must
query capabilities and degrade explicitly instead of assuming equal phone
performance and sensors.

## Hardware tiers

| Tier | Expected hardware | Input | Recommended rendering |
|---|---|---|---|
| **Lite** | Low-end smartphone, passive viewer, 3DoF tracking | Gaze, touch, temple tap | Simple geometry and materials, limited lighting, optional effects disabled |
| **Standard** | Mid-range smartphone plus controller or second phone | Lite + gamepad, remote controller, optional hands | Intermediate lighting, textures, and a measured higher scene budget |
| **Pro** | Hardware with advanced cameras and sensors | 6DoF, hand tracking, spatial peripherals | Advanced tracking, denser scenes, and effects enabled from thermal measurements |

An experience should retain its primary function on Lite. Standard and Pro add
fidelity or interaction methods unless a module explicitly declares a higher
minimum tier.

## Data flow

Physical sensors, network sources, cameras, and touch are translated by a
`VrInputDriver`. The driver borrows an event from the fixed pool and submits it
to `VrInputArbiter`. Accepted synchronous callbacks update interaction,
locomotion, scene, camera, or physics state. `RenderPass` and `VRRenderer` read
that state to produce a mono or stereo view; they do not read input hardware.

Priority is `remotePhone/touch > peripherals > gaze`. Active higher-priority
input suppresses lower-priority actions for the configurable 400 ms window.
Gaze hover remains available, while gaze dwell selection is suppressed.

## Zero-GC contract

The hot path is `acquire → submit → synchronous callback → release`.
`VrInputEventPool` preallocates a fixed number of objects, clears payload
references on release, rejects double release and foreign events, and exposes
`assertNoLeaks()` for verification. Pool exhaustion throws instead of silently
allocating. Drivers must also reuse their own payload buffers at 60–120 Hz.

The stream-based `VrInputEventBus` remains available for compatible,
low-frequency asynchronous flows. The synchronous arbiter is the preferred
per-frame path.

## Parent/child remote controller

The child publishes its `VrControllerProfile` and sequenced
`VrRemotePoseFrame`s through `VrControllerTransport`. The reference
`VrLocalSocketTransport` authenticates a one-time token and synchronously owns a
snapshot of any pooled event before asynchronous I/O. On the visor,
`VrRemoteControllerSession` drops stale frames, feeds `VrLaserPointerDriver`,
updates `ControllerState`, and maintains `VrControllerAvatarNode`.

Lite deliberately uses a stable head-relative avatar position. Accelerometer
samples are transported but never double-integrated into translation. Optional
range must identify its measurement source and confidence; range plus
orientation is not a complete 3D position. The reference LAN socket is
authenticated but unencrypted, so untrusted networks require a secure transport.

## Modern 3D scene and hybrid tracing

New experiences should pass `VrlizateScene` to `VREngine`. It is the modern
mesh scene graph with PBR materials, lights, spatial UI, fog, and culling. The
historical `VRScene` is a compatibility API for 2D particle-style elements and
is not the foundation of the high-quality Home or demos.

Hybrid tracing remains an object-space enhancement to rasterization. Once per
scene revision, `RenderPass` casts a fixed number of CPU rays from the nearest
lit receivers toward the primary light and intersects cached world AABBs. Both
stereo eyes reuse the resulting direct-light visibility. The default budgets
are 0/18/36 rays per frame and 10/16/24 sphere segments for Lite, Standard, and
High respectively.

This is intentionally not per-pixel path tracing: it provides bounded object
shadows, not global illumination or ray-traced reflections. Triangle- or
pixel-level tracing would require a BVH, GPU compute, and a separately profiled
thermal tier while preserving the Lite raster path.

## Extension rules

- Input modules translate hardware and never depend on a scene.
- Interaction maps accepted intent to selection, grabbing, or locomotion.
- Scene modules own spatial state and never open sensor subscriptions.
- Rendering draws current state and never decides user intent.
- Effects are optional and can be disabled by hardware tier.
- New drivers must document permissions, frequency, sensors, and minimum tier,
  reuse high-frequency storage, detach cleanly, and include arbitration and pool
  lifecycle tests.
