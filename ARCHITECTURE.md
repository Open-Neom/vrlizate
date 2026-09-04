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

## Extension rules

- Input modules translate hardware and never depend on a scene.
- Interaction maps accepted intent to selection, grabbing, or locomotion.
- Scene modules own spatial state and never open sensor subscriptions.
- Rendering draws current state and never decides user intent.
- Effects are optional and can be disabled by hardware tier.
- New drivers must document permissions, frequency, sensors, and minimum tier,
  reuse high-frequency storage, detach cleanly, and include arbitration and pool
  lifecycle tests.
