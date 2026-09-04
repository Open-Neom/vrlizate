# Contribuir a VRlizate / Contributing to VRlizate

**Español** · [English](#english)

Gracias por ayudar a construir VR accesible para smartphones. Buscamos cambios
pequeños, medibles y fáciles de entender por estudiantes y desarrolladores que
entran por primera vez al proyecto.

## Antes de empezar

1. Revisa [README.md](README.md) y [ARCHITECTURE.md](ARCHITECTURE.md).
2. Busca un issue existente antes de crear otro.
3. Para una API pública o cambio arquitectónico grande, abre primero una
   propuesta con el problema, alternativas y efecto en Lite/Standard/Pro.
4. No incluyas claves, datos personales, modelos o assets sin una licencia
   compatible.

## Entorno local

```bash
git clone https://github.com/Open-Neom/vrlizate.git
cd vrlizate
flutter pub get
flutter test
flutter analyze
```

La aplicación de ejemplo usa el paquete local:

```bash
cd example
flutter pub get
flutter run
```

## Flujo de una contribución

1. Crea una rama enfocada en un solo cambio.
2. Escribe o actualiza tests antes de considerar completo el comportamiento.
3. Implementa con las API y límites descritos en `ARCHITECTURE.md`.
4. Ejecuta formato, análisis y toda la suite.
5. Describe en el PR qué cambió, por qué y en qué hardware fue probado.

```bash
dart format lib test example/lib
flutter test
flutter analyze
```

No reformatees archivos sin relación con tu cambio.

## Añadir un driver de entrada

- Implementa `VrInputDriver` y utiliza un `VrInputSource` específico.
- Inicia suscripciones en `attach` y cancélalas en `detach`.
- Para eventos por frame usa `acquire/submit/release` con `finally`.
- Reutiliza mapas, buffers y estados del payload; el pool solo evita crear el
  contenedor `VrInputEvent`.
- No conserves eventos recibidos por un listener del árbitro.
- Añade tests de desconexión, prioridad, histéresis y liberación del pool.
- Documenta permisos, sensores, frecuencia de muestreo y tier mínimo.

## Rendimiento y compatibilidad

- Lite es el baseline: una mejora Pro no debe degradar silenciosamente Lite.
- Las rutas a 60–120 Hz no deben crear objetos por evento.
- Un nuevo efecto debe poder desactivarse.
- No uses tiempos absolutos en tests de histéresis; inyecta `VrInputClock`.
- Los benchmarks deben medir después de una fase de calentamiento y evitar
  límites dependientes de una sola máquina cuando no sean necesarios.
- Una optimización debe conservar tests de corrección, no solo mejorar tiempo.

## Checklist del pull request

- [ ] El cambio tiene un propósito y alcance claros.
- [ ] Hay tests para comportamiento nuevo o corregido.
- [ ] `flutter test` pasa.
- [ ] `flutter analyze` termina sin warnings.
- [ ] Se actualizó documentación pública cuando corresponde.
- [ ] Se evaluó el nivel Lite/Standard/Pro afectado.
- [ ] No se introdujeron asignaciones por frame evitables.
- [ ] No hay secretos ni dependencias/assets sin licencia clara.

Para fallos de seguridad no publiques secretos ni una prueba explotable en un
issue público. Utiliza un aviso privado de seguridad del repositorio cuando esté
disponible.

Al enviar una contribución aceptas que se distribuya bajo Apache License 2.0.

---

## English

Thank you for helping build accessible smartphone VR. We favor small,
measurable changes that remain approachable to students and first-time
contributors.

## Before starting

1. Read [README.md](README.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
2. Search existing issues before opening one.
3. Propose large public API or architecture changes first, including the
   problem, alternatives, and Lite/Standard/Pro impact.
4. Never commit secrets, personal data, or assets/models without a compatible
   license.

## Local workflow

```bash
git clone https://github.com/Open-Neom/vrlizate.git
cd vrlizate
flutter pub get
flutter test
flutter analyze
```

The example application uses the local package:

```bash
cd example
flutter pub get
flutter run
```

Create a focused branch, add or update tests, implement within the boundaries
in `ARCHITECTURE.md`, and run:

```bash
dart format lib test example/lib
flutter test
flutter analyze
```

Do not reformat unrelated files.

## Input-driver rules

- Implement `VrInputDriver` with the most specific `VrInputSource`.
- Start subscriptions in `attach` and cancel them in `detach`.
- Use `acquire/submit/release` with `finally` for per-frame events.
- Reuse payload maps, buffers, and state; the pool only removes
  `VrInputEvent` container allocation.
- Never retain an event received by an arbiter listener.
- Test disconnect, priority, hysteresis, and pool release behavior.
- Document permissions, sensors, sample frequency, and minimum hardware tier.

## Performance and compatibility

Lite is the baseline. Per-frame paths must not allocate one object per event,
new effects must be optional, hysteresis tests must inject `VrInputClock`, and
optimizations must preserve correctness tests. Benchmarks should warm up first
and avoid unnecessary limits tied to one development machine.

## Pull-request checklist

- [ ] The change has one clear purpose and scope.
- [ ] New or corrected behavior has tests.
- [ ] `flutter test` passes.
- [ ] `flutter analyze` has no warnings.
- [ ] Public documentation is updated where needed.
- [ ] Lite/Standard/Pro impact was considered.
- [ ] No avoidable per-frame allocations were introduced.
- [ ] No secrets or unclearly licensed dependencies/assets are included.

For security reports, do not publish secrets or an exploitable proof in a
public issue. Use a private repository security advisory when available.

By submitting a contribution, you agree that it is distributed under the
Apache License 2.0.
