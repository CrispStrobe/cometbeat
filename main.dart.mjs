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
      _1298: x0 => globalThis.Module_soloud._malloc(x0),
      _1299: (x0,x1,x2) => globalThis.Module_soloud.setValue(x0,x1,x2),
      _1301: x0 => globalThis.Module_soloud._free(x0),
      _1303: (x0,x1,x2,x3) => globalThis.Module_soloud._initEngine(x0,x1,x2,x3),
      _1306: (x0,x1) => globalThis.Module_soloud.getValue(x0,x1),
      _1309: () => globalThis.Module_soloud._dispose(),
      _1310: () => globalThis.Module_soloud._isInited(),
      _1311: (x0,x1,x2,x3,x4) => globalThis.Module_soloud._loadMem(x0,x1,x2,x3,x4),
      _1330: (x0,x1) => globalThis.Module_soloud._setPause(x0,x1),
      _1334: (x0,x1,x2,x3,x4,x5,x6) => globalThis.Module_soloud._play(x0,x1,x2,x3,x4,x5,x6),
      _1335: x0 => globalThis.Module_soloud._stop(x0),
      _1336: x0 => globalThis.Module_soloud._disposeSound(x0),
      _1337: () => globalThis.Module_soloud._disposeAllSound(),
      _1343: () => globalThis.Module_soloud._getVisualizationEnabled(),
      _1350: (x0,x1) => globalThis.Module_soloud._seek(x0,x1),
      _1359: x0 => globalThis.Module_soloud._getIsValidVoiceHandle(x0),
      _1374: (x0,x1,x2) => globalThis.Module_soloud._fadeVolume(x0,x1,x2),
      _1407: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1408: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      _1409: (x0,x1) => x0.createElement(x1),
      _1416: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1426: x0 => x0.click(),
      _1427: x0 => x0.remove(),
      _1430: x0 => globalThis.URL.revokeObjectURL(x0),
      _1433: x0 => globalThis.URL.createObjectURL(x0),
      _1439: (x0,x1) => x0.querySelector(x1),
      _1440: (x0,x1) => x0.append(x1),
      _1442: x0 => ({audio: x0}),
      _1443: (x0,x1) => x0.getUserMedia(x1),
      _1444: x0 => x0.getAudioTracks(),
      _1445: x0 => x0.stop(),
      _1446: (x0,x1) => x0.removeTrack(x1),
      _1447: x0 => x0.close(),
      _1448: (x0,x1) => x0.warn(x1),
      _1449: x0 => x0.getSettings(),
      _1450: x0 => ({sampleRate: x0}),
      _1451: x0 => new AudioContext(x0),
      _1452: () => new AudioContext(),
      _1454: x0 => x0.resume(),
      _1455: (x0,x1) => x0.connect(x1),
      _1456: (x0,x1) => x0.createMediaStreamSource(x1),
      _1457: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1457(f,arguments.length,x0) }),
      _1458: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1458(f,arguments.length,x0) }),
      _1459: (x0,x1) => x0.addModule(x1),
      _1460: x0 => ({parameterData: x0}),
      _1461: (x0,x1,x2) => new AudioWorkletNode(x0,x1,x2),
      _1462: x0 => ({name: x0}),
      _1463: (x0,x1) => x0.query(x1),
      _1469: x0 => x0.disconnect(),
      _1476: x0 => ({type: x0}),
      _1477: (x0,x1) => new Blob(x0,x1),
      _1480: x0 => globalThis.MediaRecorder.isTypeSupported(x0),
      _1488: (x0,x1) => x0.appendChild(x1),
      _1489: (x0,x1) => x0.item(x1),
      _1490: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1490(f,arguments.length,x0) }),
      _1491: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1492: (x0,x1) => x0.createMediaElementSource(x1),
      _1493: x0 => x0.createGain(),
      _1494: x0 => x0.createStereoPanner(),
      _1495: x0 => x0.load(),
      _1496: x0 => x0.play(),
      _1497: x0 => x0.pause(),
      _1498: (x0,x1) => x0.getItem(x1),
      _1499: (x0,x1) => x0.removeItem(x1),
      _1500: (x0,x1,x2) => x0.setItem(x1,x2),
      _1501: () => new SpeechSynthesisUtterance(),
      _1502: x0 => x0.pause(),
      _1503: x0 => x0.resume(),
      _1504: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1504(f,arguments.length,x0) }),
      _1505: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1505(f,arguments.length,x0) }),
      _1506: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1506(f,arguments.length,x0) }),
      _1507: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1507(f,arguments.length,x0) }),
      _1508: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1508(f,arguments.length,x0) }),
      _1509: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1509(f,arguments.length,x0) }),
      _1510: (x0,x1) => x0.speak(x1),
      _1511: x0 => x0.cancel(),
      _1512: x0 => x0.getVoices(),
      _1513: Date.now,
      _1515: s => new Date(s * 1000).getTimezoneOffset() * 60,
      _1516: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      _1517: () => typeof dartUseDateNowForTicks !== "undefined",
      _1518: () => 1000 * performance.now(),
      _1519: () => Date.now(),
      _1520: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      _1521: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      _1522: () => new WeakMap(),
      _1523: (map, o) => map.get(o),
      _1524: (map, o, v) => map.set(o, v),
      _1525: x0 => new WeakRef(x0),
      _1526: x0 => x0.deref(),
      _1527: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1527(f,arguments.length,x0) }),
      _1528: x0 => new FinalizationRegistry(x0),
      _1529: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _1531: (x0,x1) => x0.unregister(x1),
      _1533: () => globalThis.WeakRef,
      _1534: () => globalThis.FinalizationRegistry,
      _1536: x0 => x0.call(),
      _1537: s => JSON.stringify(s),
      _1538: s => printToConsole(s),
      _1539: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      _1540: (o, p, r) => o.replaceAll(p, () => r),
      _1541: (o, p, r) => o.replace(p, () => r),
      _1542: Function.prototype.call.bind(String.prototype.toLowerCase),
      _1543: s => s.toUpperCase(),
      _1544: s => s.trim(),
      _1545: s => s.trimLeft(),
      _1546: s => s.trimRight(),
      _1547: (string, times) => string.repeat(times),
      _1548: Function.prototype.call.bind(String.prototype.indexOf),
      _1549: (s, p, i) => s.lastIndexOf(p, i),
      _1550: (string, token) => string.split(token),
      _1551: Object.is,
      _1556: (o, c) => o instanceof c,
      _1557: o => Object.keys(o),
      _1560: (o,s,v) => o[s] = v,
      _1611: x0 => new Array(x0),
      _1613: x0 => x0.length,
      _1615: (x0,x1) => x0[x1],
      _1616: (x0,x1,x2) => { x0[x1] = x2 },
      _1619: (x0,x1,x2) => new DataView(x0,x1,x2),
      _1621: x0 => new Int8Array(x0),
      _1622: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      _1624: x0 => new Uint8ClampedArray(x0),
      _1626: x0 => new Int16Array(x0),
      _1628: x0 => new Uint16Array(x0),
      _1630: x0 => new Int32Array(x0),
      _1632: x0 => new Uint32Array(x0),
      _1634: x0 => new Float32Array(x0),
      _1636: x0 => new Float64Array(x0),
      _1659: () => Symbol("jsBoxedDartObjectProperty"),
      _1660: x0 => x0.random(),
      _1661: (x0,x1) => x0.getRandomValues(x1),
      _1662: () => globalThis.crypto,
      _1663: () => globalThis.Math,
      _1676: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      _1677: (handle) => clearTimeout(handle),
      _1678: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      _1679: (handle) => clearInterval(handle),
      _1680: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      _1681: () => Date.now(),
      _1682: () => new Error().stack,
      _1683: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      _1684: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      _1685: (x0,x1) => x0.exec(x1),
      _1686: (x0,x1) => x0.test(x1),
      _1687: x0 => x0.pop(),
      _1689: o => o === undefined,
      _1691: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      _1693: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      _1694: o => o instanceof RegExp,
      _1695: (l, r) => l === r,
      _1696: o => o,
      _1697: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      _1698: o => o,
      _1699: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      _1700: o => o,
      _1701: b => !!b,
      _1702: o => o.length,
      _1704: (o, i) => o[i],
      _1705: f => f.dartFunction,
      _1706: () => ({}),
      _1707: () => [],
      _1709: () => globalThis,
      _1710: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      _1712: (o, p) => o[p],
      _1713: (o, p, v) => o[p] = v,
      _1714: (o, m, a) => o[m].apply(o, a),
      _1716: o => String(o),
      _1717: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      _1718: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1718(f,arguments.length,x0) }),
      _1719: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1719(f,arguments.length,x0,x1) }),
      _1720: o => {
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
      _1721: o => [o],
      _1722: (o0, o1) => [o0, o1],
      _1723: (o0, o1, o2) => [o0, o1, o2],
      _1724: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      _1725: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      _1726: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1727: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1728: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1729: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1730: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1731: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1732: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1733: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1734: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1735: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1736: x0 => new ArrayBuffer(x0),
      _1737: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      _1739: x0 => x0.index,
      _1741: x0 => x0.flags,
      _1742: x0 => x0.multiline,
      _1743: x0 => x0.ignoreCase,
      _1744: x0 => x0.unicode,
      _1745: x0 => x0.dotAll,
      _1746: (x0,x1) => { x0.lastIndex = x1 },
      _1747: (o, p) => p in o,
      _1748: (o, p) => o[p],
      _1749: (o, p, v) => o[p] = v,
      _1752: (x0,x1) => x0.sqlite3changeset_finalize(x1),
      _1753: (x0,x1) => x0.sqlite3session_delete(x1),
      _1754: (x0,x1) => x0.sqlite3_close_v2(x1),
      _1755: (x0,x1) => x0.sqlite3_finalize(x1),
      _1756: (x0,x1) => x0.dart_sqlite3_malloc(x1),
      _1757: (x0,x1) => x0.dart_sqlite3_free(x1),
      _1759: x0 => x0.sqlite3_initialize(),
      _1765: (x0,x1,x2,x3,x4) => x0.sqlite3_open_v2(x1,x2,x3,x4),
      _1766: (x0,x1) => x0.sqlite3_extended_errcode(x1),
      _1767: (x0,x1) => x0.sqlite3_errmsg(x1),
      _1768: (x0,x1) => x0.sqlite3_errstr(x1),
      _1769: (x0,x1) => x0.sqlite3_error_offset(x1),
      _1770: (x0,x1,x2) => x0.sqlite3_extended_result_codes(x1,x2),
      _1774: (x0,x1,x2,x3,x4,x5) => x0.sqlite3_exec(x1,x2,x3,x4,x5),
      _1775: (x0,x1,x2,x3,x4,x5,x6) => x0.sqlite3_prepare_v3(x1,x2,x3,x4,x5,x6),
      _1776: (x0,x1) => x0.sqlite3_bind_parameter_count(x1),
      _1777: (x0,x1,x2) => x0.sqlite3_bind_null(x1,x2),
      _1778: (x0,x1,x2,x3) => x0.sqlite3_bind_int64(x1,x2,x3),
      _1779: (x0,x1,x2,x3) => x0.sqlite3_bind_double(x1,x2,x3),
      _1780: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_text(x1,x2,x3,x4),
      _1781: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_blob(x1,x2,x3,x4),
      _1783: (x0,x1) => x0.sqlite3_column_count(x1),
      _1784: (x0,x1,x2) => x0.sqlite3_column_name(x1,x2),
      _1785: (x0,x1,x2) => x0.sqlite3_column_type(x1,x2),
      _1786: (x0,x1,x2) => x0.sqlite3_column_int64(x1,x2),
      _1787: (x0,x1,x2) => x0.sqlite3_column_double(x1,x2),
      _1788: (x0,x1,x2) => x0.sqlite3_column_bytes(x1,x2),
      _1789: (x0,x1,x2) => x0.sqlite3_column_text(x1,x2),
      _1790: (x0,x1,x2) => x0.sqlite3_column_blob(x1,x2),
      _1807: (x0,x1) => x0.sqlite3_step(x1),
      _1808: (x0,x1) => x0.sqlite3_reset(x1),
      _1834: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1834(f,arguments.length,x0) }),
      _1835: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1835(f,arguments.length,x0,x1) }),
      _1836: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1836(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1837: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1837(f,arguments.length,x0,x1,x2) }),
      _1838: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1838(f,arguments.length,x0,x1,x2,x3) }),
      _1839: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1839(f,arguments.length,x0,x1,x2,x3) }),
      _1840: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1840(f,arguments.length,x0,x1,x2) }),
      _1841: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1841(f,arguments.length,x0,x1) }),
      _1842: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1842(f,arguments.length,x0,x1) }),
      _1843: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1843(f,arguments.length,x0) }),
      _1844: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1844(f,arguments.length,x0,x1,x2,x3) }),
      _1845: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1845(f,arguments.length,x0,x1,x2,x3) }),
      _1846: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1846(f,arguments.length,x0,x1) }),
      _1847: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1847(f,arguments.length,x0,x1) }),
      _1848: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1848(f,arguments.length,x0,x1) }),
      _1849: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1849(f,arguments.length,x0,x1) }),
      _1850: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1850(f,arguments.length,x0,x1) }),
      _1851: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1851(f,arguments.length,x0,x1) }),
      _1852: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1852(f,arguments.length,x0) }),
      _1853: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1853(f,arguments.length,x0,x1,x2) }),
      _1854: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1854(f,arguments.length,x0) }),
      _1855: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1855(f,arguments.length,x0) }),
      _1856: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1856(f,arguments.length,x0) }),
      _1857: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1857(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1858: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1858(f,arguments.length,x0,x1,x2,x3) }),
      _1859: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1859(f,arguments.length,x0,x1,x2,x3) }),
      _1860: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1860(f,arguments.length,x0,x1,x2,x3) }),
      _1861: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1861(f,arguments.length,x0,x1) }),
      _1862: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1862(f,arguments.length,x0,x1) }),
      _1863: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1863(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1864: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1864(f,arguments.length,x0,x1) }),
      _1865: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1865(f,arguments.length,x0,x1) }),
      _1866: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1866(f,arguments.length,x0,x1,x2) }),
      _1867: (x0,x1,x2) => x0.instantiateStreaming(x1,x2),
      _1871: (x0,x1) => new URL(x0,x1),
      _1872: (x0,x1) => globalThis.fetch(x0,x1),
      _1874: x0 => globalThis.BigInt(x0),
      _1875: x0 => globalThis.Number(x0),
      _1897: (x0,x1,x2) => x0.open(x1,x2),
      _1902: (x0,x1) => x0.createObjectStore(x1),
      _1905: (x0,x1,x2) => x0.transaction(x1,x2),
      _1908: (x0,x1) => x0.objectStore(x1),
      _1917: (x0,x1) => x0.get(x1),
      _1922: (x0,x1,x2) => x0.put(x1,x2),
      _1924: (x0,x1) => x0.delete(x1),
      _1955: () => new XMLHttpRequest(),
      _1956: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1960: x0 => x0.send(),
      _1962: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1962(f,arguments.length,x0) }),
      _1963: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1963(f,arguments.length,x0) }),
      _1973: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1973(f,arguments.length,x0) }),
      _1981: () => globalThis.Module_soloud.wasmWorker,
      _1985: (x0,x1) => x0.item(x1),
      _1986: (x0,x1) => x0.removeChild(x1),
      _1987: x0 => new Blob(x0),
      _1989: () => new FileReader(),
      _1990: (x0,x1) => x0.readAsArrayBuffer(x1),
      _1991: () => new AbortController(),
      _1992: x0 => x0.abort(),
      _1993: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      _1994: (x0,x1) => globalThis.fetch(x0,x1),
      _1995: (x0,x1) => x0.get(x1),
      _1996: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1996(f,arguments.length,x0,x1,x2) }),
      _1997: (x0,x1) => x0.forEach(x1),
      _1998: x0 => x0.getReader(),
      _1999: x0 => x0.cancel(),
      _2000: x0 => x0.read(),
      _2001: (x0,x1) => x0.key(x1),
      _2002: (x0,x1) => x0.contains(x1),
      _2003: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2003(f,arguments.length,x0) }),
      _2004: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2004(f,arguments.length,x0) }),
      _2005: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2005(f,arguments.length,x0) }),
      _2006: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2006(f,arguments.length,x0) }),
      _2007: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2007(f,arguments.length,x0) }),
      _2008: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2008(f,arguments.length,x0) }),
      _2009: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2009(f,arguments.length,x0) }),
      _2010: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2010(f,arguments.length,x0) }),
      _2011: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2011(f,arguments.length,x0) }),
      _2012: x0 => x0.getAllKeys(),
      _2013: x0 => x0.getAll(),
      _2014: o => o instanceof Array,
      _2015: (a, i) => a.splice(i, 1)[0],
      _2017: (a, l) => a.length = l,
      _2018: a => a.pop(),
      _2019: (a, i) => a.splice(i, 1),
      _2020: (a, s) => a.join(s),
      _2021: (a, s, e) => a.slice(s, e),
      _2022: (a, s, e) => a.splice(s, e),
      _2023: (a, b) => a == b ? 0 : (a > b ? 1 : -1),
      _2024: a => a.length,
      _2025: (a, l) => a.length = l,
      _2026: (a, i) => a[i],
      _2027: (a, i, v) => a[i] = v,
      _2029: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      _2030: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      _2032: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      _2033: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      _2034: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      _2035: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      _2036: o => o instanceof Uint8ClampedArray,
      _2037: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      _2038: o => o instanceof Uint16Array,
      _2039: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      _2040: o => o instanceof Int16Array,
      _2041: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      _2042: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      _2043: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      _2044: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      _2045: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      _2047: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      _2048: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      _2049: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      _2050: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      _2051: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      _2052: (a, i) => a.push(i),
      _2053: (t, s) => t.set(s),
      _2054: l => new DataView(new ArrayBuffer(l)),
      _2055: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      _2056: o => o.byteLength,
      _2057: o => o.buffer,
      _2058: o => o.byteOffset,
      _2059: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      _2060: (b, o) => new DataView(b, o),
      _2061: (b, o, l) => new DataView(b, o, l),
      _2062: Function.prototype.call.bind(DataView.prototype.getUint8),
      _2063: Function.prototype.call.bind(DataView.prototype.setUint8),
      _2064: Function.prototype.call.bind(DataView.prototype.getInt8),
      _2065: Function.prototype.call.bind(DataView.prototype.setInt8),
      _2066: Function.prototype.call.bind(DataView.prototype.getUint16),
      _2067: Function.prototype.call.bind(DataView.prototype.setUint16),
      _2068: Function.prototype.call.bind(DataView.prototype.getInt16),
      _2069: Function.prototype.call.bind(DataView.prototype.setInt16),
      _2070: Function.prototype.call.bind(DataView.prototype.getUint32),
      _2071: Function.prototype.call.bind(DataView.prototype.setUint32),
      _2072: Function.prototype.call.bind(DataView.prototype.getInt32),
      _2073: Function.prototype.call.bind(DataView.prototype.setInt32),
      _2074: Function.prototype.call.bind(DataView.prototype.getBigUint64),
      _2076: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      _2077: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      _2078: Function.prototype.call.bind(DataView.prototype.getFloat32),
      _2079: Function.prototype.call.bind(DataView.prototype.setFloat32),
      _2080: Function.prototype.call.bind(DataView.prototype.getFloat64),
      _2081: Function.prototype.call.bind(DataView.prototype.setFloat64),
      _2082: Function.prototype.call.bind(Number.prototype.toString),
      _2083: Function.prototype.call.bind(BigInt.prototype.toString),
      _2084: Function.prototype.call.bind(Number.prototype.toString),
      _2085: (d, digits) => d.toFixed(digits),
      _2100: () => globalThis.globalThis.glintVorbis,
      _2101: x0 => x0.init(),
      _2102: x0 => x0.ready(),
      _2103: (x0,x1) => x0.decodeSync(x1),
      _2104: x0 => x0.pcm,
      _2105: x0 => x0.channels,
      _2106: x0 => x0.frames,
      _2107: () => globalThis.globalThis.glintCodec,
      _2108: x0 => x0.init(),
      _2109: x0 => x0.ready(),
      _2110: (x0,x1,x2,x3,x4,x5,x6,x7) => x0.encodeSync(x1,x2,x3,x4,x5,x6,x7),
      _2111: (x0,x1) => x0.decodeSync(x1),
      _2112: x0 => x0.pcm,
      _2113: x0 => x0.sampleRate,
      _2114: x0 => x0.channels,
      _2115: x0 => x0.frames,
      _2118: () => globalThis.console,
      _2157: (x0,x1) => x0.error(x1),
      _2214: (x0,x1) => { x0.responseType = x1 },
      _2215: x0 => x0.response,
      _2649: (x0,x1) => { x0.download = x1 },
      _2674: (x0,x1) => { x0.href = x1 },
      _2893: x0 => x0.error,
      _2895: (x0,x1) => { x0.src = x1 },
      _2900: (x0,x1) => { x0.crossOrigin = x1 },
      _2903: (x0,x1) => { x0.preload = x1 },
      _2907: x0 => x0.currentTime,
      _2908: (x0,x1) => { x0.currentTime = x1 },
      _2909: x0 => x0.duration,
      _2914: (x0,x1) => { x0.playbackRate = x1 },
      _2923: (x0,x1) => { x0.loop = x1 },
      _2944: x0 => x0.code,
      _2945: x0 => x0.message,
      _3216: (x0,x1) => { x0.accept = x1 },
      _3230: x0 => x0.files,
      _3256: (x0,x1) => { x0.multiple = x1 },
      _3274: (x0,x1) => { x0.type = x1 },
      _3992: () => globalThis.window,
      _4032: x0 => x0.document,
      _4054: x0 => x0.navigator,
      _4311: x0 => x0.indexedDB,
      _4318: x0 => x0.localStorage,
      _4377: x0 => x0.message,
      _4425: x0 => x0.mediaDevices,
      _4427: x0 => x0.permissions,
      _4441: x0 => x0.userAgent,
      _4442: x0 => x0.vendor,
      _4492: x0 => x0.data,
      _4529: (x0,x1) => { x0.onmessage = x1 },
      _4600: (x0,x1) => { x0.onmessage = x1 },
      _4648: x0 => x0.length,
      _6034: x0 => x0.destination,
      _6035: x0 => x0.sampleRate,
      _6038: x0 => x0.state,
      _6039: x0 => x0.audioWorklet,
      _6126: (x0,x1) => { x0.value = x1 },
      _6274: x0 => x0.gain,
      _6402: x0 => x0.port,
      _6541: x0 => x0.type,
      _6582: x0 => x0.signal,
      _6594: x0 => x0.length,
      _6637: x0 => x0.baseURI,
      _6654: () => globalThis.document,
      _6736: x0 => x0.body,
      _7067: (x0,x1) => { x0.id = x1 },
      _7094: x0 => x0.children,
      _8413: x0 => x0.value,
      _8415: x0 => x0.done,
      _8579: x0 => x0.size,
      _8580: x0 => x0.type,
      _8586: x0 => x0.name,
      _8587: x0 => x0.lastModified,
      _8592: x0 => x0.length,
      _8598: x0 => x0.result,
      _9088: x0 => x0.url,
      _9090: x0 => x0.status,
      _9092: x0 => x0.statusText,
      _9093: x0 => x0.headers,
      _9094: x0 => x0.body,
      _9106: x0 => x0.instance,
      _9108: () => globalThis.WebAssembly,
      _9130: x0 => x0.exports,
      _9138: x0 => x0.buffer,
      _9480: x0 => x0.state,
      _10140: x0 => x0.sampleRate,
      _10152: x0 => x0.channelCount,
      _10542: x0 => x0.result,
      _10548: (x0,x1) => { x0.onsuccess = x1 },
      _10550: (x0,x1) => { x0.onerror = x1 },
      _10554: (x0,x1) => { x0.onupgradeneeded = x1 },
      _10573: x0 => x0.objectStoreNames,
      _10647: (x0,x1) => { x0.oncomplete = x1 },
      _10649: (x0,x1) => { x0.onerror = x1 },
      _12697: x0 => x0.name,
      _12794: x0 => x0.href,
      _13414: () => globalThis.console,
      _13442: () => globalThis.speechSynthesis,
      _13443: (x0,x1) => { x0.lang = x1 },
      _13445: (x0,x1) => { x0.pitch = x1 },
      _13448: (x0,x1) => { x0.rate = x1 },
      _13450: (x0,x1) => { x0.text = x1 },
      _13451: (x0,x1) => { x0.voice = x1 },
      _13452: x0 => x0.voice,
      _13454: (x0,x1) => { x0.volume = x1 },
      _13455: (x0,x1) => { x0.onstart = x1 },
      _13456: (x0,x1) => { x0.onend = x1 },
      _13457: (x0,x1) => { x0.onpause = x1 },
      _13458: (x0,x1) => { x0.onresume = x1 },
      _13459: (x0,x1) => { x0.onerror = x1 },
      _13460: (x0,x1) => { x0.onboundary = x1 },
      _13462: x0 => x0.lang,
      _13463: x0 => x0.localService,
      _13464: x0 => x0.name,

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
