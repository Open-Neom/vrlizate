// Copyright 2026 The VRlizate SDK Authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
//
// Direct Native Interop C/Objective-C & JNI ABI declarations parsed by
// `package:ffigen` (`dart run tool/ffigen.dart`).

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "jni.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Standard C heap helpers (zero external package dependency)
// ---------------------------------------------------------------------------
void* malloc(size_t size);
void free(void* ptr);

// ---------------------------------------------------------------------------
// Apple Objective-C Runtime ABI (`libobjc.A.dylib` on iOS & macOS)
// ---------------------------------------------------------------------------
typedef struct VrObjCClass VrObjCClass;
typedef struct VrObjCSel VrObjCSel;
typedef struct VrObjCObject VrObjCObject;

/// Exact 64-bit layout of Apple CoreMotion `CMRotationRate` (rad/s).
typedef struct VrCMRotationRate {
  double x;
  double y;
  double z;
} VrCMRotationRate;

/// Exact 64-bit layout of Apple CoreMotion `CMQuaternion`.
typedef struct VrCMQuaternion {
  double x;
  double y;
  double z;
  double w;
} VrCMQuaternion;

VrObjCClass* objc_getClass(const char* name);
VrObjCSel* sel_registerName(const char* str);
void* objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void* pool);

/// Exposed via symbol address so callers cast `objc_msgSend` to each target
/// selector's exact C ABI prototype on ARM64 and x86_64.
void objc_msgSend(void);

#ifdef __cplusplus
}
#endif
