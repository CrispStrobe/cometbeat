// Compiles a dart2wasm-generated main module from `source` which can then
// instantiatable via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm modules from `bytes` which is then
// instantiatable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

// DEPRECATED: Please use `compile` or `compileStreaming` to get a compiled app,
// use `instantiate` method to get an instantiated app and then call
// `invokeMain` to invoke the main function.
export async function instantiate(modulePromise, importObjectPromise) {
  var moduleOrCompiledApp = await modulePromise;
  if (!(moduleOrCompiledApp instanceof CompiledApp)) {
    moduleOrCompiledApp = new CompiledApp(moduleOrCompiledApp);
  }
  const instantiatedApp = await moduleOrCompiledApp.instantiate(await importObjectPromise);
  return instantiatedApp.instantiatedModule;
}

// DEPRECATED: Please use `compile` or `compileStreaming` to get a compiled app,
// use `instantiate` method to get an instantiated app and then call
// `invokeMain` to invoke the main function.
export const invoke = (moduleInstance, ...args) => {
  moduleInstance.exports.$invokeMain(args);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arugments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `load-ids` option is passed. Each load ID maps to one
  //   or more wasm files as specified in the emitted JSON file. It also takes a
  //   callback that should be invoked for each loaded module with 2 arugments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDynamicModule` is a JS function that takes two string names matching,
  //   in order, a wasm file produced by the dart2wasm compiler during dynamic
  //   module compilation and a corresponding js file produced by the same
  //   compilation. It also takes a callback that should be invoked with the
  //   loaded module in a format supported by `WebAssembly.compile` or
  //   `WebAssembly.compileStreaming` and the result of using the JS 'import'
  //   API on the js file path. It should return a Promise that resolves when
  //   all the modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports,
      {loadDeferredModules, loadDynamicModule, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            _1: (decoder, codeUnits) => decoder.decode(codeUnits),
      _2: () => new TextDecoder("utf-8", {fatal: true}),
      _3: () => new TextDecoder("utf-8", {fatal: false}),
      _4: (s) => +s,
      _5: x0 => new Uint8Array(x0),
      _6: (x0,x1,x2) => x0.set(x1,x2),
      _7: (x0,x1) => x0.transferFromImageBitmap(x1),
      _8: x0 => x0.arrayBuffer(),
      _9: (x0,x1,x2) => x0.slice(x1,x2),
      _10: (x0,x1) => x0.decode(x1),
      _11: (x0,x1) => x0.segment(x1),
      _12: () => new TextDecoder(),
      _14: x0 => x0.buffer,
      _15: x0 => x0.wasmMemory,
      _16: () => globalThis.window._flutter_skwasmInstance,
      _17: x0 => x0.rasterStartMilliseconds,
      _18: x0 => x0.rasterEndMilliseconds,
      _19: x0 => x0.imageBitmaps,
      _135: (x0,x1) => x0.appendChild(x1),
      _166: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _167: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      _168: (x0,x1) => new OffscreenCanvas(x0,x1),
      _169: x0 => x0.remove(),
      _170: (x0,x1) => x0.append(x1),
      _172: x0 => x0.unlock(),
      _173: x0 => x0.getReader(),
      _174: (x0,x1) => x0.item(x1),
      _175: x0 => x0.next(),
      _176: x0 => x0.now(),
      _183: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._183(f,arguments.length,x0) }),
      _184: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _186: (x0,x1) => x0.getModifierState(x1),
      _187: x0 => x0.preventDefault(),
      _188: x0 => x0.stopPropagation(),
      _189: (x0,x1) => x0.removeProperty(x1),
      _190: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._190(f,arguments.length,x0) }),
      _191: x0 => new window.FinalizationRegistry(x0),
      _192: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _194: (x0,x1) => x0.unregister(x1),
      _195: (x0,x1) => x0.prepend(x1),
      _196: x0 => new Intl.Locale(x0),
      _197: (x0,x1) => x0.observe(x1),
      _198: x0 => x0.disconnect(),
      _199: (x0,x1) => x0.getAttribute(x1),
      _200: (x0,x1) => x0.contains(x1),
      _201: (x0,x1) => x0.querySelector(x1),
      _202: (x0,x1) => x0.matchMedia(x1),
      _203: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._203(f,arguments.length,x0) }),
      _204: (x0,x1,x2) => x0.call(x1,x2),
      _205: x0 => x0.blur(),
      _206: x0 => x0.hasFocus(),
      _207: (x0,x1) => x0.removeAttribute(x1),
      _208: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _209: (x0,x1) => x0.hasAttribute(x1),
      _210: (x0,x1) => x0.getModifierState(x1),
      _211: (x0,x1) => x0.createTextNode(x1),
      _212: x0 => x0.getBoundingClientRect(),
      _213: (x0,x1) => x0.replaceWith(x1),
      _214: (x0,x1) => x0.contains(x1),
      _215: (x0,x1) => x0.closest(x1),
      _653: x0 => new Uint8Array(x0),
      _656: () => globalThis.window.flutterConfiguration,
      _658: x0 => x0.assetBase,
      _663: x0 => x0.canvasKitMaximumSurfaces,
      _664: x0 => x0.debugShowSemanticsNodes,
      _665: x0 => x0.hostElement,
      _666: x0 => x0.multiViewEnabled,
      _667: x0 => x0.nonce,
      _669: x0 => x0.fontFallbackBaseUrl,
      _679: x0 => x0.console,
      _680: x0 => x0.devicePixelRatio,
      _681: x0 => x0.document,
      _682: x0 => x0.history,
      _683: x0 => x0.innerHeight,
      _684: x0 => x0.innerWidth,
      _685: x0 => x0.location,
      _686: x0 => x0.navigator,
      _687: x0 => x0.visualViewport,
      _688: x0 => x0.performance,
      _689: x0 => x0.parent,
      _693: (x0,x1) => x0.getComputedStyle(x1),
      _694: x0 => x0.screen,
      _695: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._695(f,arguments.length,x0) }),
      _696: (x0,x1) => x0.requestAnimationFrame(x1),
      _700: (x0,x1) => x0.warn(x1),
      _703: x0 => globalThis.parseFloat(x0),
      _704: () => globalThis.window,
      _705: () => globalThis.Intl,
      _706: () => globalThis.Symbol,
      _709: x0 => x0.clipboard,
      _710: x0 => x0.maxTouchPoints,
      _711: x0 => x0.vendor,
      _712: x0 => x0.language,
      _713: x0 => x0.platform,
      _714: x0 => x0.userAgent,
      _715: (x0,x1) => x0.vibrate(x1),
      _716: x0 => x0.languages,
      _717: x0 => x0.documentElement,
      _718: (x0,x1) => x0.querySelector(x1),
      _719: (x0,x1) => x0.querySelectorAll(x1),
      _721: (x0,x1) => x0.createElement(x1),
      _724: (x0,x1) => x0.createEvent(x1),
      _725: x0 => x0.activeElement,
      _728: x0 => x0.head,
      _729: x0 => x0.body,
      _731: (x0,x1) => { x0.title = x1 },
      _734: x0 => x0.visibilityState,
      _735: () => globalThis.document,
      _736: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._736(f,arguments.length,x0) }),
      _737: (x0,x1) => x0.dispatchEvent(x1),
      _745: x0 => x0.target,
      _747: x0 => x0.timeStamp,
      _748: x0 => x0.type,
      _750: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      _757: x0 => x0.firstChild,
      _761: x0 => x0.parentElement,
      _763: (x0,x1) => { x0.textContent = x1 },
      _764: x0 => x0.parentNode,
      _766: (x0,x1) => x0.removeChild(x1),
      _767: x0 => x0.isConnected,
      _775: x0 => x0.clientHeight,
      _776: x0 => x0.clientWidth,
      _777: x0 => x0.offsetHeight,
      _778: x0 => x0.offsetWidth,
      _779: x0 => x0.id,
      _780: (x0,x1) => { x0.id = x1 },
      _783: (x0,x1) => { x0.spellcheck = x1 },
      _784: x0 => x0.tagName,
      _785: x0 => x0.style,
      _787: (x0,x1) => x0.querySelectorAll(x1),
      _788: (x0,x1,x2) => x0.setAttribute(x1,x2),
      _789: x0 => x0.tabIndex,
      _790: (x0,x1) => { x0.tabIndex = x1 },
      _791: (x0,x1) => x0.focus(x1),
      _792: x0 => x0.scrollTop,
      _793: (x0,x1) => { x0.scrollTop = x1 },
      _794: (x0,x1) => { x0.scrollLeft = x1 },
      _795: x0 => x0.scrollLeft,
      _796: x0 => x0.classList,
      _797: (x0,x1) => x0.scrollIntoView(x1),
      _800: (x0,x1) => { x0.className = x1 },
      _802: (x0,x1) => x0.getElementsByClassName(x1),
      _803: x0 => x0.click(),
      _804: (x0,x1) => x0.attachShadow(x1),
      _807: x0 => x0.computedStyleMap(),
      _808: (x0,x1) => x0.get(x1),
      _814: (x0,x1) => x0.getPropertyValue(x1),
      _815: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      _816: x0 => x0.offsetLeft,
      _817: x0 => x0.offsetTop,
      _818: x0 => x0.offsetParent,
      _820: (x0,x1) => { x0.name = x1 },
      _821: x0 => x0.content,
      _822: (x0,x1) => { x0.content = x1 },
      _840: (x0,x1) => { x0.nonce = x1 },
      _845: (x0,x1) => { x0.width = x1 },
      _847: (x0,x1) => { x0.height = x1 },
      _850: (x0,x1) => x0.getContext(x1),
      _918: x0 => x0.width,
      _919: x0 => x0.height,
      _921: (x0,x1) => x0.fetch(x1),
      _922: x0 => x0.status,
      _924: x0 => x0.body,
      _925: x0 => x0.arrayBuffer(),
      _928: x0 => x0.read(),
      _929: x0 => x0.value,
      _930: x0 => x0.done,
      _938: x0 => x0.x,
      _939: x0 => x0.y,
      _942: x0 => x0.top,
      _943: x0 => x0.right,
      _944: x0 => x0.bottom,
      _945: x0 => x0.left,
      _955: x0 => x0.height,
      _956: x0 => x0.width,
      _957: x0 => x0.scale,
      _958: (x0,x1) => { x0.value = x1 },
      _961: (x0,x1) => { x0.placeholder = x1 },
      _963: (x0,x1) => { x0.name = x1 },
      _964: x0 => x0.selectionDirection,
      _965: x0 => x0.selectionStart,
      _966: x0 => x0.selectionEnd,
      _969: x0 => x0.value,
      _971: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _972: x0 => x0.readText(),
      _973: (x0,x1) => x0.writeText(x1),
      _975: x0 => x0.altKey,
      _976: x0 => x0.code,
      _977: x0 => x0.ctrlKey,
      _978: x0 => x0.key,
      _979: x0 => x0.keyCode,
      _980: x0 => x0.location,
      _981: x0 => x0.metaKey,
      _982: x0 => x0.repeat,
      _983: x0 => x0.shiftKey,
      _984: x0 => x0.isComposing,
      _986: x0 => x0.state,
      _987: (x0,x1) => x0.go(x1),
      _989: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      _990: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      _991: x0 => x0.pathname,
      _992: x0 => x0.search,
      _993: x0 => x0.hash,
      _997: x0 => x0.state,
      _1012: x0 => x0.matches,
      _1016: x0 => x0.matches,
      _1020: x0 => x0.relatedTarget,
      _1022: x0 => x0.clientX,
      _1023: x0 => x0.clientY,
      _1024: x0 => x0.offsetX,
      _1025: x0 => x0.offsetY,
      _1028: x0 => x0.button,
      _1029: x0 => x0.buttons,
      _1030: x0 => x0.ctrlKey,
      _1034: x0 => x0.pointerId,
      _1035: x0 => x0.pointerType,
      _1036: x0 => x0.pressure,
      _1037: x0 => x0.tiltX,
      _1038: x0 => x0.tiltY,
      _1039: x0 => x0.getCoalescedEvents(),
      _1042: x0 => x0.deltaX,
      _1043: x0 => x0.deltaY,
      _1044: x0 => x0.wheelDeltaX,
      _1045: x0 => x0.wheelDeltaY,
      _1046: x0 => x0.deltaMode,
      _1053: x0 => x0.changedTouches,
      _1056: x0 => x0.clientX,
      _1057: x0 => x0.clientY,
      _1060: x0 => x0.data,
      _1063: (x0,x1) => { x0.disabled = x1 },
      _1065: (x0,x1) => { x0.type = x1 },
      _1066: (x0,x1) => { x0.max = x1 },
      _1067: (x0,x1) => { x0.min = x1 },
      _1068: x0 => x0.value,
      _1069: (x0,x1) => { x0.value = x1 },
      _1070: x0 => x0.disabled,
      _1071: (x0,x1) => { x0.disabled = x1 },
      _1073: (x0,x1) => { x0.placeholder = x1 },
      _1075: (x0,x1) => { x0.name = x1 },
      _1076: (x0,x1) => { x0.autocomplete = x1 },
      _1078: x0 => x0.selectionDirection,
      _1079: x0 => x0.selectionStart,
      _1081: x0 => x0.selectionEnd,
      _1084: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _1085: (x0,x1) => x0.add(x1),
      _1087: (x0,x1) => { x0.noValidate = x1 },
      _1088: (x0,x1) => { x0.method = x1 },
      _1089: (x0,x1) => { x0.action = x1 },
      _1095: (x0,x1) => x0.getContext(x1),
      _1097: x0 => x0.convertToBlob(),
      _1114: x0 => x0.orientation,
      _1115: x0 => x0.width,
      _1116: x0 => x0.height,
      _1117: (x0,x1) => x0.lock(x1),
      _1136: x0 => new ResizeObserver(x0),
      _1139: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1139(f,arguments.length,x0,x1) }),
      _1147: x0 => x0.length,
      _1148: x0 => x0.iterator,
      _1149: x0 => x0.Segmenter,
      _1150: x0 => x0.v8BreakIterator,
      _1151: (x0,x1) => new Intl.Segmenter(x0,x1),
      _1154: x0 => x0.language,
      _1155: x0 => x0.script,
      _1156: x0 => x0.region,
      _1174: x0 => x0.done,
      _1175: x0 => x0.value,
      _1176: x0 => x0.index,
      _1180: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      _1181: (x0,x1) => x0.adoptText(x1),
      _1182: x0 => x0.first(),
      _1183: x0 => x0.next(),
      _1184: x0 => x0.current(),
      _1186: () => globalThis.window.FinalizationRegistry,
      _1197: x0 => x0.hostElement,
      _1198: x0 => x0.viewConstraints,
      _1201: x0 => x0.maxHeight,
      _1202: x0 => x0.maxWidth,
      _1203: x0 => x0.minHeight,
      _1204: x0 => x0.minWidth,
      _1205: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1205(f,arguments.length,x0) }),
      _1206: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1206(f,arguments.length,x0) }),
      _1207: (x0,x1) => ({addView: x0,removeView: x1}),
      _1210: x0 => x0.loader,
      _1211: () => globalThis._flutter,
      _1212: (x0,x1) => x0.didCreateEngineInitializer(x1),
      _1213: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1213(f,arguments.length,x0) }),
      _1214: (module,f) => finalizeWrapper(f, function() { return module.exports._1214(f,arguments.length) }),
      _1215: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      _1218: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1218(f,arguments.length,x0) }),
      _1219: x0 => ({runApp: x0}),
      _1221: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1221(f,arguments.length,x0,x1) }),
      _1222: x0 => new Promise(x0),
      _1223: x0 => x0.length,
      _1297: () => globalThis.Module_soloud._createWorkerInWasm(),
      _1298: x0 => globalThis.Module_soloud._setMixerOutputCallback(x0),
      _1299: x0 => globalThis.Module_soloud._malloc(x0),
      _1302: x0 => globalThis.Module_soloud._free(x0),
      _1305: () => globalThis.Module_soloud._stopMixerCapture(),
      _1306: () => globalThis.Module_soloud._isMixerCaptureRunning(),
      _1310: x0 => globalThis.Module_soloud._advanceMixerCaptureReadPosition(x0),
      _1313: (x0,x1,x2,x3,x4) => globalThis.Module_soloud._initEngine(x0,x1,x2,x3,x4),
      _1316: (x0,x1) => globalThis.Module_soloud.getValue(x0,x1),
      _1319: () => globalThis.Module_soloud._dispose(),
      _1320: () => globalThis.Module_soloud._isInited(),
      _1322: (x0,x1,x2,x3,x4,x5,x6,x7,x8) => globalThis.Module_soloud._setBufferStream(x0,x1,x2,x3,x4,x5,x6,x7,x8),
      _1323: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1323(f,arguments.length,x0,x1,x2) }),
      _1339: (x0,x1,x2) => globalThis.Module_soloud._addAudioDataStream(x0,x1,x2),
      _1340: x0 => globalThis.Module_soloud._setDataIsEnded(x0),
      _1350: (x0,x1) => globalThis.Module_soloud._setPause(x0,x1),
      _1355: (x0,x1,x2,x3,x4,x5,x6,x7,x8) => globalThis.Module_soloud._playWithLoopPoints(x0,x1,x2,x3,x4,x5,x6,x7,x8),
      _1364: x0 => globalThis.Module_soloud._stop(x0),
      _1365: x0 => globalThis.Module_soloud._disposeSound(x0),
      _1374: () => globalThis.Module_soloud._getVisualizationEnabled(),
      _1381: (x0,x1) => globalThis.Module_soloud._seek(x0,x1),
      _1386: (x0,x1) => globalThis.Module_soloud._setVolume(x0,x1),
      _1388: (x0,x1) => globalThis.Module_soloud._setPan(x0,x1),
      _1390: x0 => globalThis.Module_soloud._getIsValidVoiceHandle(x0),
      _1399: () => globalThis.Module_soloud._createVoiceGroup(),
      _1400: x0 => globalThis.Module_soloud._destroyVoiceGroup(x0),
      _1401: (x0,x1) => globalThis.Module_soloud._addVoiceToGroup(x0,x1),
      _1405: (x0,x1,x2) => globalThis.Module_soloud._fadeVolume(x0,x1,x2),
      _1446: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1447: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      _1448: (x0,x1) => x0.createElement(x1),
      _1455: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1465: x0 => x0.click(),
      _1466: x0 => x0.remove(),
      _1469: x0 => globalThis.URL.revokeObjectURL(x0),
      _1472: x0 => globalThis.URL.createObjectURL(x0),
      _1478: (x0,x1) => x0.querySelector(x1),
      _1479: (x0,x1) => x0.append(x1),
      _1481: x0 => ({audio: x0}),
      _1482: (x0,x1) => x0.getUserMedia(x1),
      _1483: x0 => x0.getAudioTracks(),
      _1484: x0 => x0.stop(),
      _1485: (x0,x1) => x0.removeTrack(x1),
      _1486: x0 => x0.close(),
      _1487: (x0,x1) => x0.warn(x1),
      _1488: x0 => x0.getSettings(),
      _1489: x0 => ({sampleRate: x0}),
      _1490: x0 => new AudioContext(x0),
      _1491: () => new AudioContext(),
      _1493: x0 => x0.resume(),
      _1494: (x0,x1) => x0.connect(x1),
      _1495: (x0,x1) => x0.createMediaStreamSource(x1),
      _1496: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1496(f,arguments.length,x0) }),
      _1497: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1497(f,arguments.length,x0) }),
      _1498: (x0,x1) => x0.addModule(x1),
      _1499: x0 => ({parameterData: x0}),
      _1500: (x0,x1,x2) => new AudioWorkletNode(x0,x1,x2),
      _1501: x0 => ({name: x0}),
      _1502: (x0,x1) => x0.query(x1),
      _1508: x0 => x0.disconnect(),
      _1515: x0 => ({type: x0}),
      _1516: (x0,x1) => new Blob(x0,x1),
      _1519: x0 => globalThis.MediaRecorder.isTypeSupported(x0),
      _1527: (x0,x1) => x0.appendChild(x1),
      _1528: (x0,x1) => x0.item(x1),
      _1529: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1529(f,arguments.length,x0) }),
      _1530: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1531: (x0,x1) => x0.createMediaElementSource(x1),
      _1532: x0 => x0.createGain(),
      _1533: x0 => x0.createStereoPanner(),
      _1534: x0 => x0.load(),
      _1535: x0 => x0.play(),
      _1536: x0 => x0.pause(),
      _1537: (x0,x1) => x0.getItem(x1),
      _1538: (x0,x1) => x0.removeItem(x1),
      _1539: (x0,x1,x2) => x0.setItem(x1,x2),
      _1540: () => new SpeechSynthesisUtterance(),
      _1541: x0 => x0.pause(),
      _1542: x0 => x0.resume(),
      _1543: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1543(f,arguments.length,x0) }),
      _1544: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1544(f,arguments.length,x0) }),
      _1545: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1545(f,arguments.length,x0) }),
      _1546: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1546(f,arguments.length,x0) }),
      _1547: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1547(f,arguments.length,x0) }),
      _1548: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1548(f,arguments.length,x0) }),
      _1549: (x0,x1) => x0.speak(x1),
      _1550: x0 => x0.cancel(),
      _1551: x0 => x0.getVoices(),
      _1552: (x0,x1) => x0.querySelector(x1),
      _1553: Date.now,
      _1555: s => new Date(s * 1000).getTimezoneOffset() * 60,
      _1556: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      _1557: () => typeof dartUseDateNowForTicks !== "undefined",
      _1558: () => 1000 * performance.now(),
      _1559: () => Date.now(),
      _1560: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      _1561: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      _1562: () => new WeakMap(),
      _1563: (map, o) => map.get(o),
      _1564: (map, o, v) => map.set(o, v),
      _1565: x0 => new WeakRef(x0),
      _1566: x0 => x0.deref(),
      _1567: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1567(f,arguments.length,x0) }),
      _1568: x0 => new FinalizationRegistry(x0),
      _1569: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _1571: (x0,x1) => x0.unregister(x1),
      _1573: () => globalThis.WeakRef,
      _1574: () => globalThis.FinalizationRegistry,
      _1576: x0 => x0.call(),
      _1577: s => JSON.stringify(s),
      _1578: s => printToConsole(s),
      _1579: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      _1580: (o, p, r) => o.replaceAll(p, () => r),
      _1581: (o, p, r) => o.replace(p, () => r),
      _1582: Function.prototype.call.bind(String.prototype.toLowerCase),
      _1583: s => s.toUpperCase(),
      _1584: s => s.trim(),
      _1585: s => s.trimLeft(),
      _1586: s => s.trimRight(),
      _1587: (string, times) => string.repeat(times),
      _1588: Function.prototype.call.bind(String.prototype.indexOf),
      _1589: (s, p, i) => s.lastIndexOf(p, i),
      _1590: (string, token) => string.split(token),
      _1591: Object.is,
      _1596: (o, c) => o instanceof c,
      _1597: o => Object.keys(o),
      _1600: (o,s,v) => o[s] = v,
      _1651: x0 => new Array(x0),
      _1653: x0 => x0.length,
      _1655: (x0,x1) => x0[x1],
      _1656: (x0,x1,x2) => { x0[x1] = x2 },
      _1659: (x0,x1,x2) => new DataView(x0,x1,x2),
      _1661: x0 => new Int8Array(x0),
      _1662: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      _1664: x0 => new Uint8ClampedArray(x0),
      _1666: x0 => new Int16Array(x0),
      _1668: x0 => new Uint16Array(x0),
      _1670: x0 => new Int32Array(x0),
      _1672: x0 => new Uint32Array(x0),
      _1674: x0 => new Float32Array(x0),
      _1676: x0 => new Float64Array(x0),
      _1699: () => Symbol("jsBoxedDartObjectProperty"),
      _1700: x0 => x0.random(),
      _1701: (x0,x1) => x0.getRandomValues(x1),
      _1702: () => globalThis.crypto,
      _1703: () => globalThis.Math,
      _1716: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      _1717: (handle) => clearTimeout(handle),
      _1718: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      _1719: (handle) => clearInterval(handle),
      _1720: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      _1721: () => Date.now(),
      _1722: () => new Error().stack,
      _1723: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      _1724: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      _1725: (x0,x1) => x0.exec(x1),
      _1726: (x0,x1) => x0.test(x1),
      _1727: x0 => x0.pop(),
      _1729: o => o === undefined,
      _1731: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      _1733: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      _1734: o => o instanceof RegExp,
      _1735: (l, r) => l === r,
      _1736: o => o,
      _1737: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      _1738: o => o,
      _1739: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      _1740: o => o,
      _1741: b => !!b,
      _1742: o => o.length,
      _1744: (o, i) => o[i],
      _1745: f => f.dartFunction,
      _1746: () => ({}),
      _1747: () => [],
      _1749: () => globalThis,
      _1750: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      _1752: (o, p) => o[p],
      _1753: (o, p, v) => o[p] = v,
      _1754: (o, m, a) => o[m].apply(o, a),
      _1756: o => String(o),
      _1757: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      _1758: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1758(f,arguments.length,x0) }),
      _1759: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1759(f,arguments.length,x0,x1) }),
      _1760: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      _1761: o => [o],
      _1762: (o0, o1) => [o0, o1],
      _1763: (o0, o1, o2) => [o0, o1, o2],
      _1764: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      _1765: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      _1766: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1767: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1768: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1769: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1770: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1771: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1772: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1773: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1774: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1775: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1776: x0 => new ArrayBuffer(x0),
      _1777: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      _1779: x0 => x0.index,
      _1781: x0 => x0.flags,
      _1782: x0 => x0.multiline,
      _1783: x0 => x0.ignoreCase,
      _1784: x0 => x0.unicode,
      _1785: x0 => x0.dotAll,
      _1786: (x0,x1) => { x0.lastIndex = x1 },
      _1787: (o, p) => p in o,
      _1788: (o, p) => o[p],
      _1789: (o, p, v) => o[p] = v,
      _1792: (x0,x1) => x0.sqlite3changeset_finalize(x1),
      _1793: (x0,x1) => x0.sqlite3session_delete(x1),
      _1794: (x0,x1) => x0.sqlite3_close_v2(x1),
      _1795: (x0,x1) => x0.sqlite3_finalize(x1),
      _1796: (x0,x1) => x0.dart_sqlite3_malloc(x1),
      _1797: (x0,x1) => x0.dart_sqlite3_free(x1),
      _1799: x0 => x0.sqlite3_initialize(),
      _1805: (x0,x1,x2,x3,x4) => x0.sqlite3_open_v2(x1,x2,x3,x4),
      _1806: (x0,x1) => x0.sqlite3_extended_errcode(x1),
      _1807: (x0,x1) => x0.sqlite3_errmsg(x1),
      _1808: (x0,x1) => x0.sqlite3_errstr(x1),
      _1809: (x0,x1) => x0.sqlite3_error_offset(x1),
      _1810: (x0,x1,x2) => x0.sqlite3_extended_result_codes(x1,x2),
      _1814: (x0,x1,x2,x3,x4,x5) => x0.sqlite3_exec(x1,x2,x3,x4,x5),
      _1815: (x0,x1,x2,x3,x4,x5,x6) => x0.sqlite3_prepare_v3(x1,x2,x3,x4,x5,x6),
      _1816: (x0,x1) => x0.sqlite3_bind_parameter_count(x1),
      _1817: (x0,x1,x2) => x0.sqlite3_bind_null(x1,x2),
      _1818: (x0,x1,x2,x3) => x0.sqlite3_bind_int64(x1,x2,x3),
      _1819: (x0,x1,x2,x3) => x0.sqlite3_bind_double(x1,x2,x3),
      _1820: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_text(x1,x2,x3,x4),
      _1821: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_blob(x1,x2,x3,x4),
      _1823: (x0,x1) => x0.sqlite3_column_count(x1),
      _1824: (x0,x1,x2) => x0.sqlite3_column_name(x1,x2),
      _1825: (x0,x1,x2) => x0.sqlite3_column_type(x1,x2),
      _1826: (x0,x1,x2) => x0.sqlite3_column_int64(x1,x2),
      _1827: (x0,x1,x2) => x0.sqlite3_column_double(x1,x2),
      _1828: (x0,x1,x2) => x0.sqlite3_column_bytes(x1,x2),
      _1829: (x0,x1,x2) => x0.sqlite3_column_text(x1,x2),
      _1830: (x0,x1,x2) => x0.sqlite3_column_blob(x1,x2),
      _1847: (x0,x1) => x0.sqlite3_step(x1),
      _1848: (x0,x1) => x0.sqlite3_reset(x1),
      _1874: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1874(f,arguments.length,x0) }),
      _1875: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1875(f,arguments.length,x0,x1) }),
      _1876: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1876(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1877: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1877(f,arguments.length,x0,x1,x2) }),
      _1878: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1878(f,arguments.length,x0,x1,x2,x3) }),
      _1879: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1879(f,arguments.length,x0,x1,x2,x3) }),
      _1880: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1880(f,arguments.length,x0,x1,x2) }),
      _1881: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1881(f,arguments.length,x0,x1) }),
      _1882: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1882(f,arguments.length,x0,x1) }),
      _1883: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1883(f,arguments.length,x0) }),
      _1884: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1884(f,arguments.length,x0,x1,x2,x3) }),
      _1885: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1885(f,arguments.length,x0,x1,x2,x3) }),
      _1886: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1886(f,arguments.length,x0,x1) }),
      _1887: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1887(f,arguments.length,x0,x1) }),
      _1888: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1888(f,arguments.length,x0,x1) }),
      _1889: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1889(f,arguments.length,x0,x1) }),
      _1890: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1890(f,arguments.length,x0,x1) }),
      _1891: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1891(f,arguments.length,x0,x1) }),
      _1892: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1892(f,arguments.length,x0) }),
      _1893: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1893(f,arguments.length,x0,x1,x2) }),
      _1894: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1894(f,arguments.length,x0) }),
      _1895: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1895(f,arguments.length,x0) }),
      _1896: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1896(f,arguments.length,x0) }),
      _1897: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1897(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1898: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1898(f,arguments.length,x0,x1,x2,x3) }),
      _1899: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1899(f,arguments.length,x0,x1,x2,x3) }),
      _1900: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1900(f,arguments.length,x0,x1,x2,x3) }),
      _1901: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1901(f,arguments.length,x0,x1) }),
      _1902: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1902(f,arguments.length,x0,x1) }),
      _1903: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1903(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1904: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1904(f,arguments.length,x0,x1) }),
      _1905: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1905(f,arguments.length,x0,x1) }),
      _1906: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1906(f,arguments.length,x0,x1,x2) }),
      _1907: (x0,x1,x2) => x0.instantiateStreaming(x1,x2),
      _1911: (x0,x1) => new URL(x0,x1),
      _1912: (x0,x1) => globalThis.fetch(x0,x1),
      _1914: x0 => globalThis.BigInt(x0),
      _1915: x0 => globalThis.Number(x0),
      _1937: (x0,x1,x2) => x0.open(x1,x2),
      _1942: (x0,x1) => x0.createObjectStore(x1),
      _1945: (x0,x1,x2) => x0.transaction(x1,x2),
      _1948: (x0,x1) => x0.objectStore(x1),
      _1957: (x0,x1) => x0.get(x1),
      _1962: (x0,x1,x2) => x0.put(x1,x2),
      _1964: (x0,x1) => x0.delete(x1),
      _2005: () => new XMLHttpRequest(),
      _2006: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _2010: x0 => x0.send(),
      _2012: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2012(f,arguments.length,x0) }),
      _2013: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2013(f,arguments.length,x0) }),
      _2023: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2023(f,arguments.length,x0) }),
      _2026: () => globalThis.globalThis,
      _2029: () => globalThis.Module_soloud.HEAPU8,
      _2033: () => globalThis.Module_soloud.wasmWorker,
      _2037: (x0,x1) => x0.item(x1),
      _2038: (x0,x1) => x0.removeChild(x1),
      _2039: x0 => new Blob(x0),
      _2041: () => new FileReader(),
      _2042: (x0,x1) => x0.readAsArrayBuffer(x1),
      _2043: () => new AbortController(),
      _2044: x0 => x0.abort(),
      _2045: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      _2046: (x0,x1) => globalThis.fetch(x0,x1),
      _2047: (x0,x1) => x0.get(x1),
      _2048: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._2048(f,arguments.length,x0,x1,x2) }),
      _2049: (x0,x1) => x0.forEach(x1),
      _2050: x0 => x0.getReader(),
      _2051: x0 => x0.cancel(),
      _2052: x0 => x0.read(),
      _2053: (x0,x1) => x0.key(x1),
      _2054: (x0,x1) => x0.contains(x1),
      _2055: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2055(f,arguments.length,x0) }),
      _2056: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2056(f,arguments.length,x0) }),
      _2057: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2057(f,arguments.length,x0) }),
      _2058: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2058(f,arguments.length,x0) }),
      _2059: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2059(f,arguments.length,x0) }),
      _2060: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2060(f,arguments.length,x0) }),
      _2061: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2061(f,arguments.length,x0) }),
      _2062: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2062(f,arguments.length,x0) }),
      _2063: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2063(f,arguments.length,x0) }),
      _2064: x0 => x0.getAllKeys(),
      _2065: x0 => x0.getAll(),
      _2066: o => o instanceof Array,
      _2067: (a, i) => a.splice(i, 1)[0],
      _2069: (a, l) => a.length = l,
      _2070: a => a.pop(),
      _2071: (a, i) => a.splice(i, 1),
      _2072: (a, s) => a.join(s),
      _2073: (a, s, e) => a.slice(s, e),
      _2074: (a, s, e) => a.splice(s, e),
      _2075: (a, b) => a == b ? 0 : (a > b ? 1 : -1),
      _2076: a => a.length,
      _2077: (a, l) => a.length = l,
      _2078: (a, i) => a[i],
      _2079: (a, i, v) => a[i] = v,
      _2081: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      _2082: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      _2084: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      _2085: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      _2086: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      _2087: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      _2088: o => o instanceof Uint8ClampedArray,
      _2089: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      _2090: o => o instanceof Uint16Array,
      _2091: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      _2092: o => o instanceof Int16Array,
      _2093: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      _2094: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      _2095: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      _2096: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      _2097: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      _2099: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      _2100: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      _2101: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      _2102: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      _2103: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      _2104: (a, i) => a.push(i),
      _2105: (t, s) => t.set(s),
      _2106: l => new DataView(new ArrayBuffer(l)),
      _2107: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      _2108: o => o.byteLength,
      _2109: o => o.buffer,
      _2110: o => o.byteOffset,
      _2111: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      _2112: (b, o) => new DataView(b, o),
      _2113: (b, o, l) => new DataView(b, o, l),
      _2114: Function.prototype.call.bind(DataView.prototype.getUint8),
      _2115: Function.prototype.call.bind(DataView.prototype.setUint8),
      _2116: Function.prototype.call.bind(DataView.prototype.getInt8),
      _2117: Function.prototype.call.bind(DataView.prototype.setInt8),
      _2118: Function.prototype.call.bind(DataView.prototype.getUint16),
      _2119: Function.prototype.call.bind(DataView.prototype.setUint16),
      _2120: Function.prototype.call.bind(DataView.prototype.getInt16),
      _2121: Function.prototype.call.bind(DataView.prototype.setInt16),
      _2122: Function.prototype.call.bind(DataView.prototype.getUint32),
      _2123: Function.prototype.call.bind(DataView.prototype.setUint32),
      _2124: Function.prototype.call.bind(DataView.prototype.getInt32),
      _2125: Function.prototype.call.bind(DataView.prototype.setInt32),
      _2126: Function.prototype.call.bind(DataView.prototype.getBigUint64),
      _2128: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      _2129: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      _2130: Function.prototype.call.bind(DataView.prototype.getFloat32),
      _2131: Function.prototype.call.bind(DataView.prototype.setFloat32),
      _2132: Function.prototype.call.bind(DataView.prototype.getFloat64),
      _2133: Function.prototype.call.bind(DataView.prototype.setFloat64),
      _2134: Function.prototype.call.bind(Number.prototype.toString),
      _2135: Function.prototype.call.bind(BigInt.prototype.toString),
      _2136: Function.prototype.call.bind(Number.prototype.toString),
      _2137: (d, digits) => d.toFixed(digits),
      _2152: () => globalThis.globalThis.glintVorbis,
      _2153: x0 => x0.init(),
      _2154: x0 => x0.ready(),
      _2155: (x0,x1) => x0.decodeSync(x1),
      _2156: x0 => x0.pcm,
      _2157: x0 => x0.channels,
      _2158: x0 => x0.frames,
      _2159: () => globalThis.globalThis.glintCodec,
      _2160: x0 => x0.init(),
      _2161: x0 => x0.ready(),
      _2162: x0 => x0.version(),
      _2163: (x0,x1,x2,x3,x4,x5,x6,x7) => x0.encodeSync(x1,x2,x3,x4,x5,x6,x7),
      _2164: (x0,x1) => x0.decodeSync(x1),
      _2165: x0 => x0.pcm,
      _2166: x0 => x0.sampleRate,
      _2167: x0 => x0.channels,
      _2168: x0 => x0.frames,
      _2174: () => globalThis.console,
      _2213: (x0,x1) => x0.error(x1),
      _2270: (x0,x1) => { x0.responseType = x1 },
      _2271: x0 => x0.response,
      _2705: (x0,x1) => { x0.download = x1 },
      _2730: (x0,x1) => { x0.href = x1 },
      _2949: x0 => x0.error,
      _2951: (x0,x1) => { x0.src = x1 },
      _2956: (x0,x1) => { x0.crossOrigin = x1 },
      _2959: (x0,x1) => { x0.preload = x1 },
      _2963: x0 => x0.currentTime,
      _2964: (x0,x1) => { x0.currentTime = x1 },
      _2965: x0 => x0.duration,
      _2970: (x0,x1) => { x0.playbackRate = x1 },
      _2979: (x0,x1) => { x0.loop = x1 },
      _3000: x0 => x0.code,
      _3001: x0 => x0.message,
      _3272: (x0,x1) => { x0.accept = x1 },
      _3286: x0 => x0.files,
      _3312: (x0,x1) => { x0.multiple = x1 },
      _3330: (x0,x1) => { x0.type = x1 },
      _3580: (x0,x1) => { x0.src = x1 },
      _3582: (x0,x1) => { x0.type = x1 },
      _3586: (x0,x1) => { x0.async = x1 },
      _3600: (x0,x1) => { x0.charset = x1 },
      _4048: () => globalThis.window,
      _4088: x0 => x0.document,
      _4110: x0 => x0.navigator,
      _4367: x0 => x0.indexedDB,
      _4374: x0 => x0.localStorage,
      _4433: x0 => x0.message,
      _4481: x0 => x0.mediaDevices,
      _4483: x0 => x0.permissions,
      _4497: x0 => x0.userAgent,
      _4498: x0 => x0.vendor,
      _4548: x0 => x0.data,
      _4585: (x0,x1) => { x0.onmessage = x1 },
      _4656: (x0,x1) => { x0.onmessage = x1 },
      _4704: x0 => x0.length,
      _6090: x0 => x0.destination,
      _6094: x0 => x0.state,
      _6095: x0 => x0.audioWorklet,
      _6182: (x0,x1) => { x0.value = x1 },
      _6330: x0 => x0.gain,
      _6458: x0 => x0.port,
      _6597: x0 => x0.type,
      _6638: x0 => x0.signal,
      _6650: x0 => x0.length,
      _6693: x0 => x0.baseURI,
      _6710: () => globalThis.document,
      _6792: x0 => x0.body,
      _6794: x0 => x0.head,
      _7121: x0 => x0.id,
      _7122: (x0,x1) => { x0.id = x1 },
      _7149: x0 => x0.children,
      _8468: x0 => x0.value,
      _8470: x0 => x0.done,
      _8634: x0 => x0.size,
      _8635: x0 => x0.type,
      _8641: x0 => x0.name,
      _8642: x0 => x0.lastModified,
      _8647: x0 => x0.length,
      _8653: x0 => x0.result,
      _9143: x0 => x0.url,
      _9145: x0 => x0.status,
      _9147: x0 => x0.statusText,
      _9148: x0 => x0.headers,
      _9149: x0 => x0.body,
      _9161: x0 => x0.instance,
      _9163: () => globalThis.WebAssembly,
      _9185: x0 => x0.exports,
      _9193: x0 => x0.buffer,
      _9535: x0 => x0.state,
      _10195: x0 => x0.sampleRate,
      _10207: x0 => x0.channelCount,
      _10597: x0 => x0.result,
      _10603: (x0,x1) => { x0.onsuccess = x1 },
      _10605: (x0,x1) => { x0.onerror = x1 },
      _10609: (x0,x1) => { x0.onupgradeneeded = x1 },
      _10628: x0 => x0.objectStoreNames,
      _10702: (x0,x1) => { x0.oncomplete = x1 },
      _10704: (x0,x1) => { x0.onerror = x1 },
      _12752: x0 => x0.name,
      _12849: x0 => x0.href,
      _13469: () => globalThis.console,
      _13497: x0 => globalThis.Wakelock.toggle(x0),
      _13499: () => globalThis.speechSynthesis,
      _13500: (x0,x1) => { x0.lang = x1 },
      _13502: (x0,x1) => { x0.pitch = x1 },
      _13505: (x0,x1) => { x0.rate = x1 },
      _13507: (x0,x1) => { x0.text = x1 },
      _13508: (x0,x1) => { x0.voice = x1 },
      _13509: x0 => x0.voice,
      _13511: (x0,x1) => { x0.volume = x1 },
      _13512: (x0,x1) => { x0.onstart = x1 },
      _13513: (x0,x1) => { x0.onend = x1 },
      _13514: (x0,x1) => { x0.onpause = x1 },
      _13515: (x0,x1) => { x0.onresume = x1 },
      _13516: (x0,x1) => { x0.onerror = x1 },
      _13517: (x0,x1) => { x0.onboundary = x1 },
      _13519: x0 => x0.lang,
      _13520: x0 => x0.localService,
      _13521: x0 => x0.name,

    };

    const baseImports = {
      dart2wasm: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });
    dartInstance.exports.$setThisModule(dartInstance);

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
