import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import '../../src/third_party/vr_direct_interop.g.dart';
import 'vr_direct_native_interop.dart';

final VrDirectCoreMotion directCoreMotionInstance = _IoDirectCoreMotion();
final VrDirectDeviceBridge directDeviceBridgeInstance = _IoDirectDeviceBridge();

// ---------------------------------------------------------------------------
// Shared FFI C-string & Objective-C selector helpers
// ---------------------------------------------------------------------------

typedef _ObjCId = ffi.Pointer<VrObjCObject>;
typedef _ObjCSel = ffi.Pointer<VrObjCSel>;
typedef _ObjCCls = ffi.Pointer<VrObjCClass>;

typedef _MsgId0Native = _ObjCId Function(_ObjCId, _ObjCSel);
typedef _MsgId0Dart = _ObjCId Function(_ObjCId, _ObjCSel);

typedef _MsgClsId0Native = _ObjCId Function(_ObjCCls, _ObjCSel);
typedef _MsgClsId0Dart = _ObjCId Function(_ObjCCls, _ObjCSel);

typedef _MsgBool0Native = ffi.Bool Function(_ObjCId, _ObjCSel);
typedef _MsgBool0Dart = bool Function(_ObjCId, _ObjCSel);

typedef _MsgInt64Native = ffi.Int64 Function(_ObjCId, _ObjCSel);
typedef _MsgInt64Dart = int Function(_ObjCId, _ObjCSel);

typedef _MsgUint64Native = ffi.Uint64 Function(_ObjCId, _ObjCSel);
typedef _MsgUint64Dart = int Function(_ObjCId, _ObjCSel);

typedef _MsgDouble0Native = ffi.Double Function(_ObjCId, _ObjCSel);
typedef _MsgDouble0Dart = double Function(_ObjCId, _ObjCSel);

typedef _MsgVoid0Native = ffi.Void Function(_ObjCId, _ObjCSel);
typedef _MsgVoid0Dart = void Function(_ObjCId, _ObjCSel);

typedef _MsgSetDoubleNative = ffi.Void Function(_ObjCId, _ObjCSel, ffi.Double);
typedef _MsgSetDoubleDart = void Function(_ObjCId, _ObjCSel, double);

typedef _MsgCharPtr0Native = ffi.Pointer<ffi.Char> Function(_ObjCId, _ObjCSel);
typedef _MsgCharPtr0Dart = ffi.Pointer<ffi.Char> Function(_ObjCId, _ObjCSel);

typedef _MsgRotRateNative = VrCMRotationRate Function(_ObjCId, _ObjCSel);
typedef _MsgRotRateDart = VrCMRotationRate Function(_ObjCId, _ObjCSel);

typedef _MsgQuatNative = VrCMQuaternion Function(_ObjCId, _ObjCSel);
typedef _MsgQuatDart = VrCMQuaternion Function(_ObjCId, _ObjCSel);

final class _AppleObjCRuntime {
  _AppleObjCRuntime._(this.bindings)
    : msgId0 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgId0Native>>()
          .asFunction<_MsgId0Dart>(isLeaf: true),
      msgClsId0 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgClsId0Native>>()
          .asFunction<_MsgClsId0Dart>(isLeaf: true),
      msgBool0 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgBool0Native>>()
          .asFunction<_MsgBool0Dart>(isLeaf: true),
      msgInt64 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgInt64Native>>()
          .asFunction<_MsgInt64Dart>(isLeaf: true),
      msgUint64 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgUint64Native>>()
          .asFunction<_MsgUint64Dart>(isLeaf: true),
      msgDouble0 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgDouble0Native>>()
          .asFunction<_MsgDouble0Dart>(isLeaf: true),
      msgVoid0 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgVoid0Native>>()
          .asFunction<_MsgVoid0Dart>(),
      msgSetDouble = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgSetDoubleNative>>()
          .asFunction<_MsgSetDoubleDart>(),
      msgCharPtr0 = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgCharPtr0Native>>()
          .asFunction<_MsgCharPtr0Dart>(isLeaf: true),
      msgRotRate = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgRotRateNative>>()
          .asFunction<_MsgRotRateDart>(isLeaf: true),
      msgQuat = bindings.addresses.objc_msgSend
          .cast<ffi.NativeFunction<_MsgQuatNative>>()
          .asFunction<_MsgQuatDart>(isLeaf: true);

  static final _AppleObjCRuntime? instance = _tryOpen();

  final VrDirectInteropBindings bindings;
  final _MsgId0Dart msgId0;
  final _MsgClsId0Dart msgClsId0;
  final _MsgBool0Dart msgBool0;
  final _MsgInt64Dart msgInt64;
  final _MsgUint64Dart msgUint64;
  final _MsgDouble0Dart msgDouble0;
  final _MsgVoid0Dart msgVoid0;
  final _MsgSetDoubleDart msgSetDouble;
  final _MsgCharPtr0Dart msgCharPtr0;
  final _MsgRotRateDart msgRotRate;
  final _MsgQuatDart msgQuat;

  final Map<String, _ObjCSel> _selectors = <String, _ObjCSel>{};
  final Map<String, _ObjCCls> _classes = <String, _ObjCCls>{};

  static _AppleObjCRuntime? _tryOpen() {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    try {
      // Load Foundation explicitly so NSProcessInfo is always registered.
      try {
        ffi.DynamicLibrary.open(
          '/System/Library/Frameworks/Foundation.framework/Foundation',
        );
      } on Object {
        // Already resident in process.
      }
      final lib = ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
      return _AppleObjCRuntime._(VrDirectInteropBindings(lib));
    } on Object {
      return null;
    }
  }

  _ObjCSel sel(String name) {
    final hit = _selectors[name];
    if (hit != null) return hit;
    final ptr = withCString(name, bindings.sel_registerName);
    _selectors[name] = ptr;
    return ptr;
  }

  _ObjCCls cls(String name) {
    final hit = _classes[name];
    if (hit != null) return hit;
    final ptr = withCString(name, bindings.objc_getClass);
    if (ptr != ffi.nullptr) _classes[name] = ptr;
    return ptr;
  }

  T withCString<T>(String s, T Function(ffi.Pointer<ffi.Char>) fn) {
    final bytes = utf8.encode(s);
    final raw = bindings.malloc(bytes.length + 1).cast<ffi.Uint8>();
    if (raw == ffi.nullptr) {
      throw StateError('Out of native memory allocating C string.');
    }
    try {
      raw.asTypedList(bytes.length).setAll(0, bytes);
      raw[bytes.length] = 0;
      return fn(raw.cast<ffi.Char>());
    } finally {
      bindings.free(raw.cast<ffi.Void>());
    }
  }

  String? nsStringToDart(_ObjCId nsStr) {
    if (nsStr == ffi.nullptr) return null;
    final utf8Ptr = msgCharPtr0(nsStr, sel('UTF8String')).cast<ffi.Uint8>();
    if (utf8Ptr == ffi.nullptr) return null;
    var len = 0;
    while (len < 4096 && utf8Ptr[len] != 0) {
      len++;
    }
    return utf8.decode(utf8Ptr.asTypedList(len), allowMalformed: true);
  }
}

// ---------------------------------------------------------------------------
// Direct Apple CoreMotion (`CMMotionManager`) — Zero-Channel 100 Hz FFI
// ---------------------------------------------------------------------------

final class _IoDirectCoreMotion implements VrDirectCoreMotion {
  bool _probed = false;
  _ObjCId _manager = ffi.nullptr;
  int _activeListeners = 0;

  void _ensureProbed() {
    if (_probed) return;
    _probed = true;
    final objc = _AppleObjCRuntime.instance;
    if (objc == null) return;
    try {
      ffi.DynamicLibrary.open(
        '/System/Library/Frameworks/CoreMotion.framework/CoreMotion',
      );
      final cmClass = objc.cls('CMMotionManager');
      if (cmClass == ffi.nullptr) return;
      final allocated = objc.msgClsId0(cmClass, objc.sel('alloc'));
      if (allocated == ffi.nullptr) return;
      // Retained (+1) singleton owned for the process lifetime.
      _manager = objc.msgId0(allocated, objc.sel('init'));
    } on Object {
      _manager = ffi.nullptr;
    }
  }

  @override
  bool get isSupported {
    _ensureProbed();
    return _manager != ffi.nullptr;
  }

  @override
  bool get isDeviceMotionAvailable {
    _ensureProbed();
    final objc = _AppleObjCRuntime.instance;
    if (objc == null || _manager == ffi.nullptr) return false;
    return objc.msgBool0(_manager, objc.sel('isDeviceMotionAvailable'));
  }

  @override
  bool startUpdates({double intervalSeconds = 0.01}) {
    if (!isDeviceMotionAvailable) return false;
    final objc = _AppleObjCRuntime.instance!;
    _activeListeners++;
    final clamped = intervalSeconds.clamp(0.002, 0.2);
    objc.msgSetDouble(
      _manager,
      objc.sel('setDeviceMotionUpdateInterval:'),
      clamped,
    );
    if (!objc.msgBool0(_manager, objc.sel('isDeviceMotionActive'))) {
      objc.msgVoid0(_manager, objc.sel('startDeviceMotionUpdates'));
    }
    return true;
  }

  @override
  void stopUpdates() {
    final objc = _AppleObjCRuntime.instance;
    if (objc == null || _manager == ffi.nullptr) return;
    if (_activeListeners > 0) _activeListeners--;
    if (_activeListeners == 0 &&
        objc.msgBool0(_manager, objc.sel('isDeviceMotionActive'))) {
      objc.msgVoid0(_manager, objc.sel('stopDeviceMotionUpdates'));
    }
  }

  @override
  VrDirectMotionSample? readSampleSync() {
    final objc = _AppleObjCRuntime.instance;
    if (objc == null || _manager == ffi.nullptr) return null;
    final pool = objc.bindings.objc_autoreleasePoolPush();
    try {
      final motion = objc.msgId0(_manager, objc.sel('deviceMotion'));
      if (motion == ffi.nullptr) return null;
      final rate = objc.msgRotRate(motion, objc.sel('rotationRate'));
      final attitude = objc.msgId0(motion, objc.sel('attitude'));
      var qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0;
      if (attitude != ffi.nullptr) {
        final q = objc.msgQuat(attitude, objc.sel('quaternion'));
        qx = q.x;
        qy = q.y;
        qz = q.z;
        qw = q.w;
      }
      final tsSec = objc.msgDouble0(motion, objc.sel('timestamp'));
      return VrDirectMotionSample(
        rx: rate.x,
        ry: rate.y,
        rz: rate.z,
        qx: qx,
        qy: qy,
        qz: qz,
        qw: qw,
        timestampMicros: (tsSec * 1e6).round(),
      );
    } finally {
      objc.bindings.objc_autoreleasePoolPop(pool);
    }
  }
}

// ---------------------------------------------------------------------------
// Direct Android JNI C-ABI Helper (`JNI_GetCreatedJavaVMs` + `ActivityThread`)
// ---------------------------------------------------------------------------

final class _AndroidJniRuntime {
  _AndroidJniRuntime._(this.bindings, this.vm);

  static final _AndroidJniRuntime? instance = _tryAttachVm();

  final VrDirectInteropBindings bindings;
  final ffi.Pointer<JavaVM> vm;
  jobject _cachedGlobalAppContext = ffi.nullptr;

  static _AndroidJniRuntime? _tryAttachVm() {
    if (!Platform.isAndroid) return null;
    try {
      final proc = VrDirectInteropBindings(ffi.DynamicLibrary.process());
      final vmBuf = proc
          .malloc(ffi.sizeOf<ffi.Pointer<JavaVM>>())
          .cast<ffi.Pointer<JavaVM>>();
      final countPtr = proc.malloc(ffi.sizeOf<jsize>()).cast<jsize>();
      try {
        final rc = proc.JNI_GetCreatedJavaVMs(vmBuf, 1, countPtr);
        if (rc != JNI_OK || countPtr.value < 1 || vmBuf.value == ffi.nullptr) {
          return null;
        }
        return _AndroidJniRuntime._(proc, vmBuf.value);
      } finally {
        proc.free(vmBuf.cast());
        proc.free(countPtr.cast());
      }
    } on Object {
      return null;
    }
  }

  /// Obtains the current thread/isolate's `JNIEnv*`, attaching as a daemon
  /// thread automatically when called from a Dart background worker isolate!
  ffi.Pointer<JNIEnv>? obtainEnv() {
    final pEnvVoid = bindings
        .malloc(ffi.sizeOf<ffi.Pointer<ffi.Void>>())
        .cast<ffi.Pointer<ffi.Void>>();
    try {
      pEnvVoid.value = ffi.nullptr;
      final vtable = vm.value.ref;
      final getEnv = vtable.GetEnv
          .asFunction<
            int Function(
              ffi.Pointer<JavaVM>,
              ffi.Pointer<ffi.Pointer<ffi.Void>>,
              int,
            )
          >();
      var rc = getEnv(vm, pEnvVoid, JNI_VERSION_1_6);
      if (rc == JNI_EDETACHED) {
        final attach = vtable.AttachCurrentThreadAsDaemon
            .asFunction<
              int Function(
                ffi.Pointer<JavaVM>,
                ffi.Pointer<ffi.Pointer<JNIEnv>>,
                ffi.Pointer<ffi.Void>,
              )
            >();
        rc = attach(
          vm,
          pEnvVoid.cast<ffi.Pointer<JNIEnv>>(),
          ffi.nullptr,
        );
      }
      if (rc != JNI_OK || pEnvVoid.value == ffi.nullptr) return null;
      return pEnvVoid.value.cast<JNIEnv>();
    } finally {
      bindings.free(pEnvVoid.cast());
    }
  }

  T withCString<T>(String s, T Function(ffi.Pointer<ffi.Char>) fn) {
    final bytes = utf8.encode(s);
    final raw = bindings.malloc(bytes.length + 1).cast<ffi.Uint8>();
    if (raw == ffi.nullptr) {
      throw StateError('Out of native memory in JNI C string.');
    }
    try {
      raw.asTypedList(bytes.length).setAll(0, bytes);
      raw[bytes.length] = 0;
      return fn(raw.cast<ffi.Char>());
    } finally {
      bindings.free(raw.cast());
    }
  }

  bool clearExceptionIfAny(ffi.Pointer<JNIEnv> env) {
    final check = env.value.ref.ExceptionCheck
        .asFunction<int Function(ffi.Pointer<JNIEnv>)>();
    if (check(env) != 0) {
      final clear = env.value.ref.ExceptionClear
          .asFunction<void Function(ffi.Pointer<JNIEnv>)>();
      clear(env);
      return true;
    }
    return false;
  }

  void deleteLocal(ffi.Pointer<JNIEnv> env, jobject ref) {
    if (ref == ffi.nullptr) return;
    env.value.ref.DeleteLocalRef
        .asFunction<void Function(ffi.Pointer<JNIEnv>, jobject)>()(env, ref);
  }

  jclass findClass(ffi.Pointer<JNIEnv> env, String slashName) {
    final cls = withCString(
      slashName,
      (c) => env.value.ref.FindClass
          .asFunction<
            jclass Function(ffi.Pointer<JNIEnv>, ffi.Pointer<ffi.Char>)
          >()(env, c),
    );
    if (clearExceptionIfAny(env)) return ffi.nullptr;
    return cls;
  }

  String? jstringToDart(ffi.Pointer<JNIEnv> env, jstring str) {
    if (str == ffi.nullptr) return null;
    final getUtf = env.value.ref.GetStringUTFChars
        .asFunction<
          ffi.Pointer<ffi.Char> Function(
            ffi.Pointer<JNIEnv>,
            jstring,
            ffi.Pointer<jboolean>,
          )
        >();
    final relUtf = env.value.ref.ReleaseStringUTFChars
        .asFunction<
          void Function(ffi.Pointer<JNIEnv>, jstring, ffi.Pointer<ffi.Char>)
        >();
    final chars = getUtf(env, str, ffi.nullptr);
    if (chars == ffi.nullptr) return null;
    try {
      final u8 = chars.cast<ffi.Uint8>();
      var len = 0;
      while (len < 4096 && u8[len] != 0) {
        len++;
      }
      return utf8.decode(u8.asTypedList(len), allowMalformed: true);
    } finally {
      relUtf(env, str, chars);
    }
  }

  jstring newJString(ffi.Pointer<JNIEnv> env, String value) => withCString(
    value,
    (c) => env.value.ref.NewStringUTF
        .asFunction<
          jstring Function(ffi.Pointer<JNIEnv>, ffi.Pointer<ffi.Char>)
        >()(env, c),
  );

  String? readStaticStringField(
    ffi.Pointer<JNIEnv> env,
    jclass cls,
    String fieldName,
  ) {
    final fid = withCString(
      fieldName,
      (n) => withCString(
        'Ljava/lang/String;',
        (sig) => env.value.ref.GetStaticFieldID
            .asFunction<
              jfieldID Function(
                ffi.Pointer<JNIEnv>,
                jclass,
                ffi.Pointer<ffi.Char>,
                ffi.Pointer<ffi.Char>,
              )
            >()(env, cls, n, sig),
      ),
    );
    if (clearExceptionIfAny(env) || fid == ffi.nullptr) return null;
    final obj = env.value.ref.GetStaticObjectField
        .asFunction<jobject Function(ffi.Pointer<JNIEnv>, jclass, jfieldID)>()(
      env,
      cls,
      fid,
    );
    if (clearExceptionIfAny(env) || obj == ffi.nullptr) return null;
    try {
      return jstringToDart(env, obj);
    } finally {
      deleteLocal(env, obj);
    }
  }

  int? readStaticIntField(
    ffi.Pointer<JNIEnv> env,
    jclass cls,
    String fieldName,
  ) {
    final fid = withCString(
      fieldName,
      (n) => withCString(
        'I',
        (sig) => env.value.ref.GetStaticFieldID
            .asFunction<
              jfieldID Function(
                ffi.Pointer<JNIEnv>,
                jclass,
                ffi.Pointer<ffi.Char>,
                ffi.Pointer<ffi.Char>,
              )
            >()(env, cls, n, sig),
      ),
    );
    if (clearExceptionIfAny(env) || fid == ffi.nullptr) return null;
    final v = env.value.ref.GetStaticIntField
        .asFunction<int Function(ffi.Pointer<JNIEnv>, jclass, jfieldID)>()(
      env,
      cls,
      fid,
    );
    if (clearExceptionIfAny(env)) return null;
    return v;
  }

  /// Resolves and caches a global reference to `ActivityThread.currentApplication()`
  /// with zero Flutter plugin registration required.
  jobject obtainGlobalAppContext(ffi.Pointer<JNIEnv> env) {
    if (_cachedGlobalAppContext != ffi.nullptr) return _cachedGlobalAppContext;
    final atCls = findClass(env, 'android/app/ActivityThread');
    if (atCls == ffi.nullptr) return ffi.nullptr;
    try {
      final mid = withCString(
        'currentApplication',
        (n) => withCString(
          '()Landroid/app/Application;',
          (sig) => env.value.ref.GetStaticMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, atCls, n, sig),
        ),
      );
      if (clearExceptionIfAny(env) || mid == ffi.nullptr) return ffi.nullptr;
      final localApp = env.value.ref.CallStaticObjectMethodA
          .asFunction<
            jobject Function(
              ffi.Pointer<JNIEnv>,
              jclass,
              jmethodID,
              ffi.Pointer<jvalue>,
            )
          >()(env, atCls, mid, ffi.nullptr);
      if (clearExceptionIfAny(env) || localApp == ffi.nullptr) {
        return ffi.nullptr;
      }
      try {
        _cachedGlobalAppContext = env.value.ref.NewGlobalRef
            .asFunction<jobject Function(ffi.Pointer<JNIEnv>, jobject)>()(
          env,
          localApp,
        );
        return _cachedGlobalAppContext;
      } finally {
        deleteLocal(env, localApp);
      }
    } finally {
      deleteLocal(env, atCls);
    }
  }

  jobject getSystemService(
    ffi.Pointer<JNIEnv> env,
    jobject context,
    String serviceName,
  ) {
    final ctxCls = findClass(env, 'android/content/Context');
    if (ctxCls == ffi.nullptr) return ffi.nullptr;
    try {
      final mid = withCString(
        'getSystemService',
        (n) => withCString(
          '(Ljava/lang/String;)Ljava/lang/Object;',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, ctxCls, n, sig),
        ),
      );
      if (clearExceptionIfAny(env) || mid == ffi.nullptr) return ffi.nullptr;
      final jName = newJString(env, serviceName);
      final args = bindings.malloc(ffi.sizeOf<jvalue>()).cast<jvalue>();
      try {
        args.ref.l = jName;
        final svc = env.value.ref.CallObjectMethodA
            .asFunction<
              jobject Function(
                ffi.Pointer<JNIEnv>,
                jobject,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, context, mid, args);
        if (clearExceptionIfAny(env)) return ffi.nullptr;
        return svc;
      } finally {
        bindings.free(args.cast());
        deleteLocal(env, jName);
      }
    } finally {
      deleteLocal(env, ctxCls);
    }
  }
}

// ---------------------------------------------------------------------------
// Unified Direct Device Bridge (Apple Objective-C + Android JNI C-ABI)
// ---------------------------------------------------------------------------

final class _IoDirectDeviceBridge implements VrDirectDeviceBridge {
  @override
  bool get isAvailable =>
      _AppleObjCRuntime.instance != null || _AndroidJniRuntime.instance != null;

  @override
  int? readThermalStatusSync() {
    final objc = _AppleObjCRuntime.instance;
    if (objc != null) {
      final pool = objc.bindings.objc_autoreleasePoolPush();
      try {
        final cls = objc.cls('NSProcessInfo');
        if (cls == ffi.nullptr) return null;
        final info = objc.msgClsId0(cls, objc.sel('processInfo'));
        if (info == ffi.nullptr) return null;
        // NSProcessInfoThermalState: 0=Nominal, 1=Fair, 2=Serious, 3=Critical.
        // Map onto Android's 0..6 PowerManager scale so VrThermalGovernor acts
        // identically across iOS, macOS, and Android.
        final state = objc.msgInt64(info, objc.sel('thermalState'));
        return switch (state) {
          0 => 0,
          1 => 1,
          2 => 3,
          3 => 4,
          _ => null,
        };
      } finally {
        objc.bindings.objc_autoreleasePoolPop(pool);
      }
    }

    final jni = _AndroidJniRuntime.instance;
    if (jni != null) {
      final env = jni.obtainEnv();
      if (env == null) return null;
      final ctx = jni.obtainGlobalAppContext(env);
      if (ctx == ffi.nullptr) return null;
      final power = jni.getSystemService(env, ctx, 'power');
      if (power == ffi.nullptr) return null;
      final pmCls = jni.findClass(env, 'android/os/PowerManager');
      try {
        if (pmCls == ffi.nullptr) return null;
        final mid = jni.withCString(
          'getCurrentThermalStatus',
          (n) => jni.withCString(
            '()I',
            (sig) => env.value.ref.GetMethodID
                .asFunction<
                  jmethodID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, pmCls, n, sig),
          ),
        );
        if (jni.clearExceptionIfAny(env) || mid == ffi.nullptr) return null;
        final status = env.value.ref.CallIntMethodA
            .asFunction<
              int Function(
                ffi.Pointer<JNIEnv>,
                jobject,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, power, mid, ffi.nullptr);
        if (jni.clearExceptionIfAny(env)) return null;
        return status >= 0 && status <= 6 ? status : null;
      } finally {
        jni.deleteLocal(env, pmCls);
        jni.deleteLocal(env, power);
      }
    }
    return null;
  }

  @override
  Map<String, Object?>? readDeviceCapabilitiesSync() {
    final objc = _AppleObjCRuntime.instance;
    if (objc != null) {
      return _readAppleCapabilities(objc);
    }
    final jni = _AndroidJniRuntime.instance;
    if (jni != null) {
      return _readAndroidCapabilities(jni);
    }
    return null;
  }

  Map<String, Object?>? _readAppleCapabilities(_AppleObjCRuntime objc) {
    final pool = objc.bindings.objc_autoreleasePoolPush();
    try {
      final cls = objc.cls('NSProcessInfo');
      if (cls == ffi.nullptr) return null;
      final info = objc.msgClsId0(cls, objc.sel('processInfo'));
      if (info == ffi.nullptr) return null;
      final physBytes = objc.msgUint64(info, objc.sel('physicalMemory'));
      final cores = objc.msgUint64(info, objc.sel('activeProcessorCount'));
      final osVerObj = objc.msgId0(
        info,
        objc.sel('operatingSystemVersionString'),
      );
      final osVer = objc.nsStringToDart(osVerObj) ?? '';
      final ramMb = physBytes > 0 ? (physBytes ~/ (1024 * 1024)) : 4096;
      final thermal = readThermalStatusSync() ?? 0;
      final isIos = Platform.isIOS;
      final maxHz = (!isIos || ramMb >= 5500) ? 120.0 : 60.0;
      return <String, Object?>{
        'manufacturer': 'Apple',
        'model': isIos ? 'iPhone/iPad ($cores-core)' : 'Mac ($cores-core)',
        'brand': 'Apple',
        'device': isIos ? 'ios' : 'macos',
        'hardware': 'apple_silicon_or_x64',
        'osVersion': osVer,
        'sdkInt': 0,
        'totalRamMb': ramMb,
        'cpuCores': cores,
        'thermalStatus': thermal,
        'hasHardwareGyroscope': isIos
            ? VrDirectCoreMotion.shared.isDeviceMotionAvailable
            : false,
        'hasLinearHaptics': isIos,
        'supportsWifi5Ghz': true,
        'supportedModes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'width': 0,
            'height': 0,
            'refreshRateHz': maxHz,
          },
        ],
      };
    } finally {
      objc.bindings.objc_autoreleasePoolPop(pool);
    }
  }

  Map<String, Object?>? _readAndroidCapabilities(_AndroidJniRuntime jni) {
    final env = jni.obtainEnv();
    if (env == null) return null;
    final buildCls = jni.findClass(env, 'android/os/Build');
    final verCls = jni.findClass(env, 'android/os/Build\$VERSION');
    if (buildCls == ffi.nullptr || verCls == ffi.nullptr) {
      jni.deleteLocal(env, buildCls);
      jni.deleteLocal(env, verCls);
      return null;
    }
    try {
      final manufacturer =
          jni.readStaticStringField(env, buildCls, 'MANUFACTURER') ?? '';
      final model = jni.readStaticStringField(env, buildCls, 'MODEL') ?? '';
      final brand = jni.readStaticStringField(env, buildCls, 'BRAND') ?? '';
      final device = jni.readStaticStringField(env, buildCls, 'DEVICE') ?? '';
      final hardware =
          jni.readStaticStringField(env, buildCls, 'HARDWARE') ?? '';
      final sdkInt = jni.readStaticIntField(env, verCls, 'SDK_INT') ?? 29;
      final socModel = sdkInt >= 31
          ? (jni.readStaticStringField(env, buildCls, 'SOC_MODEL') ?? '')
          : '';
      final mpc = sdkInt >= 31
          ? (jni.readStaticIntField(env, verCls, 'MEDIA_PERFORMANCE_CLASS') ??
                0)
          : 0;

      var totalRamMb = 0;
      var hasGyro = true;
      var hasConcurrentCam = false;
      var wifi5Ghz = false;
      var staAp = false;
      var swDp = 0, wDp = 0, hDp = 0;
      var maxRefreshHz = 60.0;

      final ctx = jni.obtainGlobalAppContext(env);
      if (ctx != ffi.nullptr) {
        totalRamMb = _readAndroidTotalRamMb(jni, env, ctx);
        (hasGyro, hasConcurrentCam) = _readAndroidFeatures(jni, env, ctx);
        (wifi5Ghz, staAp) = _readAndroidWifiCaps(jni, env, ctx, sdkInt);
        (swDp, wDp, hDp) = _readAndroidConfigDp(jni, env, ctx);
        maxRefreshHz = _readAndroidDisplayRefreshHz(jni, env, ctx);
      }
      final thermal = readThermalStatusSync();

      return <String, Object?>{
        'manufacturer': manufacturer,
        'model': model,
        'brand': brand,
        'device': device,
        'hardware': hardware,
        if (socModel.isNotEmpty) 'socModel': socModel,
        'sdkInt': sdkInt,
        'mediaPerformanceClass': mpc,
        if (totalRamMb > 0) 'totalRamMb': totalRamMb,
        'hasHardwareGyroscope': hasGyro,
        'hasConcurrentCameras': hasConcurrentCam,
        'supportsWifi5Ghz': wifi5Ghz,
        'supportsStaApConcurrency': staAp,
        if (swDp > 0) 'smallestScreenWidthDp': swDp,
        if (wDp > 0) 'screenWidthDp': wDp,
        if (hDp > 0) 'screenHeightDp': hDp,
        if (thermal != null) 'thermalStatus': thermal,
        'supportedModes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'width': 0,
            'height': 0,
            'refreshRateHz': maxRefreshHz,
          },
        ],
      };
    } finally {
      jni.deleteLocal(env, buildCls);
      jni.deleteLocal(env, verCls);
    }
  }

  int _readAndroidTotalRamMb(
    _AndroidJniRuntime jni,
    ffi.Pointer<JNIEnv> env,
    jobject ctx,
  ) {
    final am = jni.getSystemService(env, ctx, 'activity');
    if (am == ffi.nullptr) return 0;
    final amCls = jni.findClass(env, 'android/app/ActivityManager');
    final miCls = jni.findClass(env, 'android/app/ActivityManager\$MemoryInfo');
    try {
      if (amCls == ffi.nullptr || miCls == ffi.nullptr) return 0;
      final initMid = jni.withCString(
        '<init>',
        (n) => jni.withCString(
          '()V',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, miCls, n, sig),
        ),
      );
      if (jni.clearExceptionIfAny(env) || initMid == ffi.nullptr) return 0;
      final memInfo = env.value.ref.NewObjectA
          .asFunction<
            jobject Function(
              ffi.Pointer<JNIEnv>,
              jclass,
              jmethodID,
              ffi.Pointer<jvalue>,
            )
          >()(env, miCls, initMid, ffi.nullptr);
      if (jni.clearExceptionIfAny(env) || memInfo == ffi.nullptr) return 0;
      try {
        final getMiMid = jni.withCString(
          'getMemoryInfo',
          (n) => jni.withCString(
            '(Landroid/app/ActivityManager\$MemoryInfo;)V',
            (sig) => env.value.ref.GetMethodID
                .asFunction<
                  jmethodID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, amCls, n, sig),
          ),
        );
        if (jni.clearExceptionIfAny(env) || getMiMid == ffi.nullptr) return 0;
        final args = jni.bindings.malloc(ffi.sizeOf<jvalue>()).cast<jvalue>();
        try {
          args.ref.l = memInfo;
          env.value.ref.CallVoidMethodA
              .asFunction<
                void Function(
                  ffi.Pointer<JNIEnv>,
                  jobject,
                  jmethodID,
                  ffi.Pointer<jvalue>,
                )
              >()(env, am, getMiMid, args);
          if (jni.clearExceptionIfAny(env)) return 0;
        } finally {
          jni.bindings.free(args.cast());
        }
        final totalFid = jni.withCString(
          'totalMem',
          (n) => jni.withCString(
            'J',
            (sig) => env.value.ref.GetFieldID
                .asFunction<
                  jfieldID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, miCls, n, sig),
          ),
        );
        if (jni.clearExceptionIfAny(env) || totalFid == ffi.nullptr) return 0;
        final bytes = env.value.ref.GetLongField
            .asFunction<int Function(ffi.Pointer<JNIEnv>, jobject, jfieldID)>()(
          env,
          memInfo,
          totalFid,
        );
        if (jni.clearExceptionIfAny(env) || bytes <= 0) return 0;
        return bytes ~/ (1024 * 1024);
      } finally {
        jni.deleteLocal(env, memInfo);
      }
    } finally {
      jni.deleteLocal(env, miCls);
      jni.deleteLocal(env, amCls);
      jni.deleteLocal(env, am);
    }
  }

  (bool, bool) _readAndroidFeatures(
    _AndroidJniRuntime jni,
    ffi.Pointer<JNIEnv> env,
    jobject ctx,
  ) {
    final ctxCls = jni.findClass(env, 'android/content/Context');
    final pmCls = jni.findClass(env, 'android/content/pm/PackageManager');
    if (ctxCls == ffi.nullptr || pmCls == ffi.nullptr) {
      jni.deleteLocal(env, ctxCls);
      jni.deleteLocal(env, pmCls);
      return (true, false);
    }
    try {
      final getPm = jni.withCString(
        'getPackageManager',
        (n) => jni.withCString(
          '()Landroid/content/pm/PackageManager;',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, ctxCls, n, sig),
        ),
      );
      if (jni.clearExceptionIfAny(env) || getPm == ffi.nullptr) {
        return (true, false);
      }
      final pm = env.value.ref.CallObjectMethodA
          .asFunction<
            jobject Function(
              ffi.Pointer<JNIEnv>,
              jobject,
              jmethodID,
              ffi.Pointer<jvalue>,
            )
          >()(env, ctx, getPm, ffi.nullptr);
      if (jni.clearExceptionIfAny(env) || pm == ffi.nullptr) {
        return (true, false);
      }
      try {
        final hasFeat = jni.withCString(
          'hasSystemFeature',
          (n) => jni.withCString(
            '(Ljava/lang/String;)Z',
            (sig) => env.value.ref.GetMethodID
                .asFunction<
                  jmethodID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, pmCls, n, sig),
          ),
        );
        if (jni.clearExceptionIfAny(env) || hasFeat == ffi.nullptr) {
          return (true, false);
        }
        bool check(String feature) {
          final jStr = jni.newJString(env, feature);
          final args = jni.bindings.malloc(ffi.sizeOf<jvalue>()).cast<jvalue>();
          try {
            args.ref.l = jStr;
            final b = env.value.ref.CallBooleanMethodA
                .asFunction<
                  int Function(
                    ffi.Pointer<JNIEnv>,
                    jobject,
                    jmethodID,
                    ffi.Pointer<jvalue>,
                  )
                >()(env, pm, hasFeat, args);
            if (jni.clearExceptionIfAny(env)) return false;
            return b != 0;
          } finally {
            jni.bindings.free(args.cast());
            jni.deleteLocal(env, jStr);
          }
        }

        return (
          check('android.hardware.sensor.gyroscope'),
          check('android.hardware.camera.concurrent'),
        );
      } finally {
        jni.deleteLocal(env, pm);
      }
    } finally {
      jni.deleteLocal(env, pmCls);
      jni.deleteLocal(env, ctxCls);
    }
  }

  (bool, bool) _readAndroidWifiCaps(
    _AndroidJniRuntime jni,
    ffi.Pointer<JNIEnv> env,
    jobject ctx,
    int sdkInt,
  ) {
    final wifi = jni.getSystemService(env, ctx, 'wifi');
    if (wifi == ffi.nullptr) return (false, false);
    final wCls = jni.findClass(env, 'android/net/wifi/WifiManager');
    try {
      if (wCls == ffi.nullptr) return (false, false);
      bool callBool(String name) {
        final mid = jni.withCString(
          name,
          (n) => jni.withCString(
            '()Z',
            (sig) => env.value.ref.GetMethodID
                .asFunction<
                  jmethodID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, wCls, n, sig),
          ),
        );
        if (jni.clearExceptionIfAny(env) || mid == ffi.nullptr) return false;
        final b = env.value.ref.CallBooleanMethodA
            .asFunction<
              int Function(
                ffi.Pointer<JNIEnv>,
                jobject,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, wifi, mid, ffi.nullptr);
        if (jni.clearExceptionIfAny(env)) return false;
        return b != 0;
      }

      final w5 = callBool('is5GHzBandSupported');
      final sta = sdkInt >= 30 && callBool('isStaApConcurrencySupported');
      return (w5, sta);
    } finally {
      jni.deleteLocal(env, wCls);
      jni.deleteLocal(env, wifi);
    }
  }

  (int, int, int) _readAndroidConfigDp(
    _AndroidJniRuntime jni,
    ffi.Pointer<JNIEnv> env,
    jobject ctx,
  ) {
    final ctxCls = jni.findClass(env, 'android/content/Context');
    final resCls = jni.findClass(env, 'android/content/res/Resources');
    final cfgCls = jni.findClass(env, 'android/content/res/Configuration');
    try {
      if (ctxCls == ffi.nullptr ||
          resCls == ffi.nullptr ||
          cfgCls == ffi.nullptr) {
        return (0, 0, 0);
      }
      final getRes = jni.withCString(
        'getResources',
        (n) => jni.withCString(
          '()Landroid/content/res/Resources;',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, ctxCls, n, sig),
        ),
      );
      if (jni.clearExceptionIfAny(env) || getRes == ffi.nullptr) {
        return (0, 0, 0);
      }
      final res = env.value.ref.CallObjectMethodA
          .asFunction<
            jobject Function(
              ffi.Pointer<JNIEnv>,
              jobject,
              jmethodID,
              ffi.Pointer<jvalue>,
            )
          >()(env, ctx, getRes, ffi.nullptr);
      if (jni.clearExceptionIfAny(env) || res == ffi.nullptr) return (0, 0, 0);
      try {
        final getCfg = jni.withCString(
          'getConfiguration',
          (n) => jni.withCString(
            '()Landroid/content/res/Configuration;',
            (sig) => env.value.ref.GetMethodID
                .asFunction<
                  jmethodID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, resCls, n, sig),
          ),
        );
        if (jni.clearExceptionIfAny(env) || getCfg == ffi.nullptr) {
          return (0, 0, 0);
        }
        final cfg = env.value.ref.CallObjectMethodA
            .asFunction<
              jobject Function(
                ffi.Pointer<JNIEnv>,
                jobject,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, res, getCfg, ffi.nullptr);
        if (jni.clearExceptionIfAny(env) || cfg == ffi.nullptr) {
          return (0, 0, 0);
        }
        try {
          int field(String name) {
            final fid = jni.withCString(
              name,
              (n) => jni.withCString(
                'I',
                (sig) => env.value.ref.GetFieldID
                    .asFunction<
                      jfieldID Function(
                        ffi.Pointer<JNIEnv>,
                        jclass,
                        ffi.Pointer<ffi.Char>,
                        ffi.Pointer<ffi.Char>,
                      )
                    >()(env, cfgCls, n, sig),
              ),
            );
            if (jni.clearExceptionIfAny(env) || fid == ffi.nullptr) return 0;
            final v = env.value.ref.GetIntField
                .asFunction<
                  int Function(ffi.Pointer<JNIEnv>, jobject, jfieldID)
                >()(env, cfg, fid);
            return jni.clearExceptionIfAny(env) ? 0 : v;
          }

          return (
            field('smallestScreenWidthDp'),
            field('screenWidthDp'),
            field('screenHeightDp'),
          );
        } finally {
          jni.deleteLocal(env, cfg);
        }
      } finally {
        jni.deleteLocal(env, res);
      }
    } finally {
      jni.deleteLocal(env, cfgCls);
      jni.deleteLocal(env, resCls);
      jni.deleteLocal(env, ctxCls);
    }
  }

  double _readAndroidDisplayRefreshHz(
    _AndroidJniRuntime jni,
    ffi.Pointer<JNIEnv> env,
    jobject ctx,
  ) {
    final wm = jni.getSystemService(env, ctx, 'window');
    if (wm == ffi.nullptr) return 60.0;
    final wmCls = jni.findClass(env, 'android/view/WindowManager');
    final dispCls = jni.findClass(env, 'android/view/Display');
    try {
      if (wmCls == ffi.nullptr || dispCls == ffi.nullptr) return 60.0;
      final getDisp = jni.withCString(
        'getDefaultDisplay',
        (n) => jni.withCString(
          '()Landroid/view/Display;',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, wmCls, n, sig),
        ),
      );
      if (jni.clearExceptionIfAny(env) || getDisp == ffi.nullptr) return 60.0;
      final disp = env.value.ref.CallObjectMethodA
          .asFunction<
            jobject Function(
              ffi.Pointer<JNIEnv>,
              jobject,
              jmethodID,
              ffi.Pointer<jvalue>,
            )
          >()(env, wm, getDisp, ffi.nullptr);
      if (jni.clearExceptionIfAny(env) || disp == ffi.nullptr) return 60.0;
      try {
        var maxHz = 60.0;
        final getRate = jni.withCString(
          'getRefreshRate',
          (n) => jni.withCString(
            '()F',
            (sig) => env.value.ref.GetMethodID
                .asFunction<
                  jmethodID Function(
                    ffi.Pointer<JNIEnv>,
                    jclass,
                    ffi.Pointer<ffi.Char>,
                    ffi.Pointer<ffi.Char>,
                  )
                >()(env, dispCls, n, sig),
          ),
        );
        if (!jni.clearExceptionIfAny(env) && getRate != ffi.nullptr) {
          final hz = env.value.ref.CallFloatMethodA
              .asFunction<
                double Function(
                  ffi.Pointer<JNIEnv>,
                  jobject,
                  jmethodID,
                  ffi.Pointer<jvalue>,
                )
              >()(env, disp, getRate, ffi.nullptr);
          if (!jni.clearExceptionIfAny(env) && hz.isFinite && hz > maxHz) {
            maxHz = hz;
          }
        }
        return maxHz;
      } finally {
        jni.deleteLocal(env, disp);
      }
    } finally {
      jni.deleteLocal(env, dispCls);
      jni.deleteLocal(env, wmCls);
      jni.deleteLocal(env, wm);
    }
  }

  @override
  int? detachAndroidSafReadOnlyFdSync(String contentUri) {
    final jni = _AndroidJniRuntime.instance;
    if (jni == null || contentUri.isEmpty) return null;
    final env = jni.obtainEnv();
    if (env == null) return null;
    final ctx = jni.obtainGlobalAppContext(env);
    if (ctx == ffi.nullptr) return null;

    final ctxCls = jni.findClass(env, 'android/content/Context');
    final crCls = jni.findClass(env, 'android/content/ContentResolver');
    final uriCls = jni.findClass(env, 'android/net/Uri');
    final pfdCls = jni.findClass(env, 'android/os/ParcelFileDescriptor');
    try {
      if (ctxCls == ffi.nullptr ||
          crCls == ffi.nullptr ||
          uriCls == ffi.nullptr ||
          pfdCls == ffi.nullptr) {
        return null;
      }
      final getCr = jni.withCString(
        'getContentResolver',
        (n) => jni.withCString(
          '()Landroid/content/ContentResolver;',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, ctxCls, n, sig),
        ),
      );
      final parseUri = jni.withCString(
        'parse',
        (n) => jni.withCString(
          '(Ljava/lang/String;)Landroid/net/Uri;',
          (sig) => env.value.ref.GetStaticMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, uriCls, n, sig),
        ),
      );
      final openFd = jni.withCString(
        'openFileDescriptor',
        (n) => jni.withCString(
          '(Landroid/net/Uri;Ljava/lang/String;)Landroid/os/ParcelFileDescriptor;',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, crCls, n, sig),
        ),
      );
      final detachFd = jni.withCString(
        'detachFd',
        (n) => jni.withCString(
          '()I',
          (sig) => env.value.ref.GetMethodID
              .asFunction<
                jmethodID Function(
                  ffi.Pointer<JNIEnv>,
                  jclass,
                  ffi.Pointer<ffi.Char>,
                  ffi.Pointer<ffi.Char>,
                )
              >()(env, pfdCls, n, sig),
        ),
      );
      if (jni.clearExceptionIfAny(env) ||
          getCr == ffi.nullptr ||
          parseUri == ffi.nullptr ||
          openFd == ffi.nullptr ||
          detachFd == ffi.nullptr) {
        return null;
      }

      final cr = env.value.ref.CallObjectMethodA
          .asFunction<
            jobject Function(
              ffi.Pointer<JNIEnv>,
              jobject,
              jmethodID,
              ffi.Pointer<jvalue>,
            )
          >()(env, ctx, getCr, ffi.nullptr);
      if (jni.clearExceptionIfAny(env) || cr == ffi.nullptr) return null;

      final jUriStr = jni.newJString(env, contentUri);
      final jModeStr = jni.newJString(env, 'r');
      final args2 = jni.bindings.malloc(ffi.sizeOf<jvalue>() * 2).cast<jvalue>();
      jobject parsedUri = ffi.nullptr;
      jobject pfd = ffi.nullptr;
      try {
        args2.ref.l = jUriStr;
        parsedUri = env.value.ref.CallStaticObjectMethodA
            .asFunction<
              jobject Function(
                ffi.Pointer<JNIEnv>,
                jclass,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, uriCls, parseUri, args2);
        if (jni.clearExceptionIfAny(env) || parsedUri == ffi.nullptr) {
          return null;
        }
        args2.ref.l = parsedUri;
        (args2 + 1).ref.l = jModeStr;
        pfd = env.value.ref.CallObjectMethodA
            .asFunction<
              jobject Function(
                ffi.Pointer<JNIEnv>,
                jobject,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, cr, openFd, args2);
        if (jni.clearExceptionIfAny(env) || pfd == ffi.nullptr) return null;
        final fd = env.value.ref.CallIntMethodA
            .asFunction<
              int Function(
                ffi.Pointer<JNIEnv>,
                jobject,
                jmethodID,
                ffi.Pointer<jvalue>,
              )
            >()(env, pfd, detachFd, ffi.nullptr);
        if (jni.clearExceptionIfAny(env) || fd < 0) return null;
        return fd;
      } finally {
        jni.bindings.free(args2.cast());
        jni.deleteLocal(env, pfd);
        jni.deleteLocal(env, parsedUri);
        jni.deleteLocal(env, jModeStr);
        jni.deleteLocal(env, jUriStr);
        jni.deleteLocal(env, cr);
      }
    } finally {
      jni.deleteLocal(env, pfdCls);
      jni.deleteLocal(env, uriCls);
      jni.deleteLocal(env, crCls);
      jni.deleteLocal(env, ctxCls);
    }
  }

  @override
  ({int javaVmAddress, int appContextAddress})? androidOpenXrHandlesSync() {
    final jni = _AndroidJniRuntime.instance;
    if (jni == null) return null;
    final env = jni.obtainEnv();
    if (env == null) return null;
    final ctx = jni.obtainGlobalAppContext(env);
    if (ctx == ffi.nullptr) return null;
    return (
      javaVmAddress: jni.vm.address,
      appContextAddress: ctx.address,
    );
  }
}
