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
      _1498: x0 => globalThis.Wakelock.toggle(x0),
      _1500: (x0,x1) => x0.getItem(x1),
      _1501: (x0,x1) => x0.removeItem(x1),
      _1502: (x0,x1,x2) => x0.setItem(x1,x2),
      _1503: () => new SpeechSynthesisUtterance(),
      _1504: x0 => x0.pause(),
      _1505: x0 => x0.resume(),
      _1506: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1506(f,arguments.length,x0) }),
      _1507: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1507(f,arguments.length,x0) }),
      _1508: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1508(f,arguments.length,x0) }),
      _1509: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1509(f,arguments.length,x0) }),
      _1510: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1510(f,arguments.length,x0) }),
      _1511: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1511(f,arguments.length,x0) }),
      _1512: (x0,x1) => x0.speak(x1),
      _1513: x0 => x0.cancel(),
      _1514: x0 => x0.getVoices(),
      _1515: Date.now,
      _1517: s => new Date(s * 1000).getTimezoneOffset() * 60,
      _1518: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      _1519: () => typeof dartUseDateNowForTicks !== "undefined",
      _1520: () => 1000 * performance.now(),
      _1521: () => Date.now(),
      _1522: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      _1523: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      _1524: () => new WeakMap(),
      _1525: (map, o) => map.get(o),
      _1526: (map, o, v) => map.set(o, v),
      _1527: x0 => new WeakRef(x0),
      _1528: x0 => x0.deref(),
      _1529: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1529(f,arguments.length,x0) }),
      _1530: x0 => new FinalizationRegistry(x0),
      _1531: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _1533: (x0,x1) => x0.unregister(x1),
      _1535: () => globalThis.WeakRef,
      _1536: () => globalThis.FinalizationRegistry,
      _1538: x0 => x0.call(),
      _1539: s => JSON.stringify(s),
      _1540: s => printToConsole(s),
      _1541: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      _1542: (o, p, r) => o.replaceAll(p, () => r),
      _1543: (o, p, r) => o.replace(p, () => r),
      _1544: Function.prototype.call.bind(String.prototype.toLowerCase),
      _1545: s => s.toUpperCase(),
      _1546: s => s.trim(),
      _1547: s => s.trimLeft(),
      _1548: s => s.trimRight(),
      _1549: (string, times) => string.repeat(times),
      _1550: Function.prototype.call.bind(String.prototype.indexOf),
      _1551: (s, p, i) => s.lastIndexOf(p, i),
      _1552: (string, token) => string.split(token),
      _1553: Object.is,
      _1558: (o, c) => o instanceof c,
      _1559: o => Object.keys(o),
      _1562: (o,s,v) => o[s] = v,
      _1613: x0 => new Array(x0),
      _1615: x0 => x0.length,
      _1617: (x0,x1) => x0[x1],
      _1618: (x0,x1,x2) => { x0[x1] = x2 },
      _1621: (x0,x1,x2) => new DataView(x0,x1,x2),
      _1623: x0 => new Int8Array(x0),
      _1624: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      _1626: x0 => new Uint8ClampedArray(x0),
      _1628: x0 => new Int16Array(x0),
      _1630: x0 => new Uint16Array(x0),
      _1632: x0 => new Int32Array(x0),
      _1634: x0 => new Uint32Array(x0),
      _1636: x0 => new Float32Array(x0),
      _1638: x0 => new Float64Array(x0),
      _1661: () => Symbol("jsBoxedDartObjectProperty"),
      _1662: x0 => x0.random(),
      _1663: (x0,x1) => x0.getRandomValues(x1),
      _1664: () => globalThis.crypto,
      _1665: () => globalThis.Math,
      _1678: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      _1679: (handle) => clearTimeout(handle),
      _1680: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      _1681: (handle) => clearInterval(handle),
      _1682: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      _1683: () => Date.now(),
      _1684: () => new Error().stack,
      _1685: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      _1686: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      _1687: (x0,x1) => x0.exec(x1),
      _1688: (x0,x1) => x0.test(x1),
      _1689: x0 => x0.pop(),
      _1691: o => o === undefined,
      _1693: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      _1695: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      _1696: o => o instanceof RegExp,
      _1697: (l, r) => l === r,
      _1698: o => o,
      _1699: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      _1700: o => o,
      _1701: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      _1702: o => o,
      _1703: b => !!b,
      _1704: o => o.length,
      _1706: (o, i) => o[i],
      _1707: f => f.dartFunction,
      _1708: () => ({}),
      _1709: () => [],
      _1711: () => globalThis,
      _1712: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      _1714: (o, p) => o[p],
      _1715: (o, p, v) => o[p] = v,
      _1716: (o, m, a) => o[m].apply(o, a),
      _1718: o => String(o),
      _1719: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      _1720: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1720(f,arguments.length,x0) }),
      _1721: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1721(f,arguments.length,x0,x1) }),
      _1722: o => {
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
      _1723: o => [o],
      _1724: (o0, o1) => [o0, o1],
      _1725: (o0, o1, o2) => [o0, o1, o2],
      _1726: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      _1727: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      _1728: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1729: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1730: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1731: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1732: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1733: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1734: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1735: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1736: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1737: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1738: x0 => new ArrayBuffer(x0),
      _1739: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      _1741: x0 => x0.index,
      _1743: x0 => x0.flags,
      _1744: x0 => x0.multiline,
      _1745: x0 => x0.ignoreCase,
      _1746: x0 => x0.unicode,
      _1747: x0 => x0.dotAll,
      _1748: (x0,x1) => { x0.lastIndex = x1 },
      _1749: (o, p) => p in o,
      _1750: (o, p) => o[p],
      _1751: (o, p, v) => o[p] = v,
      _1754: (x0,x1) => x0.sqlite3changeset_finalize(x1),
      _1755: (x0,x1) => x0.sqlite3session_delete(x1),
      _1756: (x0,x1) => x0.sqlite3_close_v2(x1),
      _1757: (x0,x1) => x0.sqlite3_finalize(x1),
      _1758: (x0,x1) => x0.dart_sqlite3_malloc(x1),
      _1759: (x0,x1) => x0.dart_sqlite3_free(x1),
      _1761: x0 => x0.sqlite3_initialize(),
      _1767: (x0,x1,x2,x3,x4) => x0.sqlite3_open_v2(x1,x2,x3,x4),
      _1768: (x0,x1) => x0.sqlite3_extended_errcode(x1),
      _1769: (x0,x1) => x0.sqlite3_errmsg(x1),
      _1770: (x0,x1) => x0.sqlite3_errstr(x1),
      _1771: (x0,x1) => x0.sqlite3_error_offset(x1),
      _1772: (x0,x1,x2) => x0.sqlite3_extended_result_codes(x1,x2),
      _1776: (x0,x1,x2,x3,x4,x5) => x0.sqlite3_exec(x1,x2,x3,x4,x5),
      _1777: (x0,x1,x2,x3,x4,x5,x6) => x0.sqlite3_prepare_v3(x1,x2,x3,x4,x5,x6),
      _1778: (x0,x1) => x0.sqlite3_bind_parameter_count(x1),
      _1779: (x0,x1,x2) => x0.sqlite3_bind_null(x1,x2),
      _1780: (x0,x1,x2,x3) => x0.sqlite3_bind_int64(x1,x2,x3),
      _1781: (x0,x1,x2,x3) => x0.sqlite3_bind_double(x1,x2,x3),
      _1782: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_text(x1,x2,x3,x4),
      _1783: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_blob(x1,x2,x3,x4),
      _1785: (x0,x1) => x0.sqlite3_column_count(x1),
      _1786: (x0,x1,x2) => x0.sqlite3_column_name(x1,x2),
      _1787: (x0,x1,x2) => x0.sqlite3_column_type(x1,x2),
      _1788: (x0,x1,x2) => x0.sqlite3_column_int64(x1,x2),
      _1789: (x0,x1,x2) => x0.sqlite3_column_double(x1,x2),
      _1790: (x0,x1,x2) => x0.sqlite3_column_bytes(x1,x2),
      _1791: (x0,x1,x2) => x0.sqlite3_column_text(x1,x2),
      _1792: (x0,x1,x2) => x0.sqlite3_column_blob(x1,x2),
      _1809: (x0,x1) => x0.sqlite3_step(x1),
      _1810: (x0,x1) => x0.sqlite3_reset(x1),
      _1836: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1836(f,arguments.length,x0) }),
      _1837: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1837(f,arguments.length,x0,x1) }),
      _1838: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1838(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1839: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1839(f,arguments.length,x0,x1,x2) }),
      _1840: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1840(f,arguments.length,x0,x1,x2,x3) }),
      _1841: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1841(f,arguments.length,x0,x1,x2,x3) }),
      _1842: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1842(f,arguments.length,x0,x1,x2) }),
      _1843: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1843(f,arguments.length,x0,x1) }),
      _1844: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1844(f,arguments.length,x0,x1) }),
      _1845: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1845(f,arguments.length,x0) }),
      _1846: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1846(f,arguments.length,x0,x1,x2,x3) }),
      _1847: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1847(f,arguments.length,x0,x1,x2,x3) }),
      _1848: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1848(f,arguments.length,x0,x1) }),
      _1849: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1849(f,arguments.length,x0,x1) }),
      _1850: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1850(f,arguments.length,x0,x1) }),
      _1851: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1851(f,arguments.length,x0,x1) }),
      _1852: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1852(f,arguments.length,x0,x1) }),
      _1853: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1853(f,arguments.length,x0,x1) }),
      _1854: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1854(f,arguments.length,x0) }),
      _1855: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1855(f,arguments.length,x0,x1,x2) }),
      _1856: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1856(f,arguments.length,x0) }),
      _1857: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1857(f,arguments.length,x0) }),
      _1858: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1858(f,arguments.length,x0) }),
      _1859: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1859(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1860: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1860(f,arguments.length,x0,x1,x2,x3) }),
      _1861: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1861(f,arguments.length,x0,x1,x2,x3) }),
      _1862: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return module.exports._1862(f,arguments.length,x0,x1,x2,x3) }),
      _1863: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1863(f,arguments.length,x0,x1) }),
      _1864: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1864(f,arguments.length,x0,x1) }),
      _1865: (module,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return module.exports._1865(f,arguments.length,x0,x1,x2,x3,x4) }),
      _1866: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1866(f,arguments.length,x0,x1) }),
      _1867: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1867(f,arguments.length,x0,x1) }),
      _1868: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1868(f,arguments.length,x0,x1,x2) }),
      _1869: (x0,x1,x2) => x0.instantiateStreaming(x1,x2),
      _1873: (x0,x1) => new URL(x0,x1),
      _1874: (x0,x1) => globalThis.fetch(x0,x1),
      _1876: x0 => globalThis.BigInt(x0),
      _1877: x0 => globalThis.Number(x0),
      _1899: (x0,x1,x2) => x0.open(x1,x2),
      _1904: (x0,x1) => x0.createObjectStore(x1),
      _1907: (x0,x1,x2) => x0.transaction(x1,x2),
      _1910: (x0,x1) => x0.objectStore(x1),
      _1919: (x0,x1) => x0.get(x1),
      _1924: (x0,x1,x2) => x0.put(x1,x2),
      _1926: (x0,x1) => x0.delete(x1),
      _1957: () => new XMLHttpRequest(),
      _1958: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1962: x0 => x0.send(),
      _1964: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1964(f,arguments.length,x0) }),
      _1965: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1965(f,arguments.length,x0) }),
      _1975: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1975(f,arguments.length,x0) }),
      _1983: () => globalThis.Module_soloud.wasmWorker,
      _1987: (x0,x1) => x0.item(x1),
      _1988: (x0,x1) => x0.removeChild(x1),
      _1989: x0 => new Blob(x0),
      _1991: () => new FileReader(),
      _1992: (x0,x1) => x0.readAsArrayBuffer(x1),
      _1993: () => new AbortController(),
      _1994: x0 => x0.abort(),
      _1995: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      _1996: (x0,x1) => globalThis.fetch(x0,x1),
      _1997: (x0,x1) => x0.get(x1),
      _1998: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._1998(f,arguments.length,x0,x1,x2) }),
      _1999: (x0,x1) => x0.forEach(x1),
      _2000: x0 => x0.getReader(),
      _2001: x0 => x0.cancel(),
      _2002: x0 => x0.read(),
      _2003: (x0,x1) => x0.key(x1),
      _2004: (x0,x1) => x0.contains(x1),
      _2005: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2005(f,arguments.length,x0) }),
      _2006: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2006(f,arguments.length,x0) }),
      _2007: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2007(f,arguments.length,x0) }),
      _2008: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2008(f,arguments.length,x0) }),
      _2009: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2009(f,arguments.length,x0) }),
      _2010: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2010(f,arguments.length,x0) }),
      _2011: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2011(f,arguments.length,x0) }),
      _2012: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2012(f,arguments.length,x0) }),
      _2013: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._2013(f,arguments.length,x0) }),
      _2014: x0 => x0.getAllKeys(),
      _2015: x0 => x0.getAll(),
      _2016: o => o instanceof Array,
      _2017: (a, i) => a.splice(i, 1)[0],
      _2019: (a, l) => a.length = l,
      _2020: a => a.pop(),
      _2021: (a, i) => a.splice(i, 1),
      _2022: (a, s) => a.join(s),
      _2023: (a, s, e) => a.slice(s, e),
      _2024: (a, s, e) => a.splice(s, e),
      _2025: (a, b) => a == b ? 0 : (a > b ? 1 : -1),
      _2026: a => a.length,
      _2027: (a, l) => a.length = l,
      _2028: (a, i) => a[i],
      _2029: (a, i, v) => a[i] = v,
      _2031: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      _2032: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      _2034: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      _2035: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      _2036: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      _2037: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      _2038: o => o instanceof Uint8ClampedArray,
      _2039: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      _2040: o => o instanceof Uint16Array,
      _2041: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      _2042: o => o instanceof Int16Array,
      _2043: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      _2044: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      _2045: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      _2046: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      _2047: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      _2049: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      _2050: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      _2051: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      _2052: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      _2053: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      _2054: (a, i) => a.push(i),
      _2055: (t, s) => t.set(s),
      _2056: l => new DataView(new ArrayBuffer(l)),
      _2057: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      _2058: o => o.byteLength,
      _2059: o => o.buffer,
      _2060: o => o.byteOffset,
      _2061: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      _2062: (b, o) => new DataView(b, o),
      _2063: (b, o, l) => new DataView(b, o, l),
      _2064: Function.prototype.call.bind(DataView.prototype.getUint8),
      _2065: Function.prototype.call.bind(DataView.prototype.setUint8),
      _2066: Function.prototype.call.bind(DataView.prototype.getInt8),
      _2067: Function.prototype.call.bind(DataView.prototype.setInt8),
      _2068: Function.prototype.call.bind(DataView.prototype.getUint16),
      _2069: Function.prototype.call.bind(DataView.prototype.setUint16),
      _2070: Function.prototype.call.bind(DataView.prototype.getInt16),
      _2071: Function.prototype.call.bind(DataView.prototype.setInt16),
      _2072: Function.prototype.call.bind(DataView.prototype.getUint32),
      _2073: Function.prototype.call.bind(DataView.prototype.setUint32),
      _2074: Function.prototype.call.bind(DataView.prototype.getInt32),
      _2075: Function.prototype.call.bind(DataView.prototype.setInt32),
      _2076: Function.prototype.call.bind(DataView.prototype.getBigUint64),
      _2078: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      _2079: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      _2080: Function.prototype.call.bind(DataView.prototype.getFloat32),
      _2081: Function.prototype.call.bind(DataView.prototype.setFloat32),
      _2082: Function.prototype.call.bind(DataView.prototype.getFloat64),
      _2083: Function.prototype.call.bind(DataView.prototype.setFloat64),
      _2084: Function.prototype.call.bind(Number.prototype.toString),
      _2085: Function.prototype.call.bind(BigInt.prototype.toString),
      _2086: Function.prototype.call.bind(Number.prototype.toString),
      _2087: (d, digits) => d.toFixed(digits),
      _2102: () => globalThis.globalThis.glintVorbis,
      _2103: x0 => x0.init(),
      _2104: x0 => x0.ready(),
      _2105: (x0,x1) => x0.decodeSync(x1),
      _2106: x0 => x0.pcm,
      _2107: x0 => x0.channels,
      _2108: x0 => x0.frames,
      _2109: () => globalThis.globalThis.glintCodec,
      _2110: x0 => x0.init(),
      _2111: x0 => x0.ready(),
      _2112: (x0,x1,x2,x3,x4,x5,x6,x7) => x0.encodeSync(x1,x2,x3,x4,x5,x6,x7),
      _2113: (x0,x1) => x0.decodeSync(x1),
      _2114: x0 => x0.pcm,
      _2115: x0 => x0.sampleRate,
      _2116: x0 => x0.channels,
      _2117: x0 => x0.frames,
      _2120: () => globalThis.console,
      _2159: (x0,x1) => x0.error(x1),
      _2216: (x0,x1) => { x0.responseType = x1 },
      _2217: x0 => x0.response,
      _2651: (x0,x1) => { x0.download = x1 },
      _2676: (x0,x1) => { x0.href = x1 },
      _2895: x0 => x0.error,
      _2897: (x0,x1) => { x0.src = x1 },
      _2902: (x0,x1) => { x0.crossOrigin = x1 },
      _2905: (x0,x1) => { x0.preload = x1 },
      _2909: x0 => x0.currentTime,
      _2910: (x0,x1) => { x0.currentTime = x1 },
      _2911: x0 => x0.duration,
      _2916: (x0,x1) => { x0.playbackRate = x1 },
      _2925: (x0,x1) => { x0.loop = x1 },
      _2946: x0 => x0.code,
      _2947: x0 => x0.message,
      _3218: (x0,x1) => { x0.accept = x1 },
      _3232: x0 => x0.files,
      _3258: (x0,x1) => { x0.multiple = x1 },
      _3276: (x0,x1) => { x0.type = x1 },
      _3525: x0 => x0.src,
      _3526: (x0,x1) => { x0.src = x1 },
      _3528: (x0,x1) => { x0.type = x1 },
      _3532: (x0,x1) => { x0.async = x1 },
      _3546: (x0,x1) => { x0.charset = x1 },
      _3994: () => globalThis.window,
      _4034: x0 => x0.document,
      _4056: x0 => x0.navigator,
      _4313: x0 => x0.indexedDB,
      _4320: x0 => x0.localStorage,
      _4379: x0 => x0.message,
      _4427: x0 => x0.mediaDevices,
      _4429: x0 => x0.permissions,
      _4443: x0 => x0.userAgent,
      _4444: x0 => x0.vendor,
      _4494: x0 => x0.data,
      _4531: (x0,x1) => { x0.onmessage = x1 },
      _4602: (x0,x1) => { x0.onmessage = x1 },
      _4650: x0 => x0.length,
      _6036: x0 => x0.destination,
      _6037: x0 => x0.sampleRate,
      _6040: x0 => x0.state,
      _6041: x0 => x0.audioWorklet,
      _6128: (x0,x1) => { x0.value = x1 },
      _6276: x0 => x0.gain,
      _6404: x0 => x0.port,
      _6543: x0 => x0.type,
      _6584: x0 => x0.signal,
      _6596: x0 => x0.length,
      _6639: x0 => x0.baseURI,
      _6656: () => globalThis.document,
      _6738: x0 => x0.body,
      _6740: x0 => x0.head,
      _7069: (x0,x1) => { x0.id = x1 },
      _7096: x0 => x0.children,
      _8415: x0 => x0.value,
      _8417: x0 => x0.done,
      _8581: x0 => x0.size,
      _8582: x0 => x0.type,
      _8588: x0 => x0.name,
      _8589: x0 => x0.lastModified,
      _8594: x0 => x0.length,
      _8600: x0 => x0.result,
      _9090: x0 => x0.url,
      _9092: x0 => x0.status,
      _9094: x0 => x0.statusText,
      _9095: x0 => x0.headers,
      _9096: x0 => x0.body,
      _9108: x0 => x0.instance,
      _9110: () => globalThis.WebAssembly,
      _9132: x0 => x0.exports,
      _9140: x0 => x0.buffer,
      _9482: x0 => x0.state,
      _10142: x0 => x0.sampleRate,
      _10154: x0 => x0.channelCount,
      _10544: x0 => x0.result,
      _10550: (x0,x1) => { x0.onsuccess = x1 },
      _10552: (x0,x1) => { x0.onerror = x1 },
      _10556: (x0,x1) => { x0.onupgradeneeded = x1 },
      _10575: x0 => x0.objectStoreNames,
      _10649: (x0,x1) => { x0.oncomplete = x1 },
      _10651: (x0,x1) => { x0.onerror = x1 },
      _12699: x0 => x0.name,
      _12796: x0 => x0.href,
      _13416: () => globalThis.console,
      _13444: () => globalThis.speechSynthesis,
      _13445: (x0,x1) => { x0.lang = x1 },
      _13447: (x0,x1) => { x0.pitch = x1 },
      _13450: (x0,x1) => { x0.rate = x1 },
      _13452: (x0,x1) => { x0.text = x1 },
      _13453: (x0,x1) => { x0.voice = x1 },
      _13454: x0 => x0.voice,
      _13456: (x0,x1) => { x0.volume = x1 },
      _13457: (x0,x1) => { x0.onstart = x1 },
      _13458: (x0,x1) => { x0.onend = x1 },
      _13459: (x0,x1) => { x0.onpause = x1 },
      _13460: (x0,x1) => { x0.onresume = x1 },
      _13461: (x0,x1) => { x0.onerror = x1 },
      _13462: (x0,x1) => { x0.onboundary = x1 },
      _13464: x0 => x0.lang,
      _13465: x0 => x0.localService,
      _13466: x0 => x0.name,

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
