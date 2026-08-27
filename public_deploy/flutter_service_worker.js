'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "efe9fdb88c8cc9b360b1790462cacadc",
"assets/AssetManifest.bin.json": "18041f6e2df852a9b8cd5f050e83376d",
"assets/AssetManifest.json": "81957c2b1f5d8be710e14a2ce70a8b28",
"assets/assets/images/logo.png": "fbd75733eb32d1cf1aca4739747d0565",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "a6057a91ca608cab7761a9ceb2090b42",
"assets/NOTICES": "f998fdf391e2a8f963194f42522148d2",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/reown_appkit/lib/modal/assets/account_copy.svg": "3dfb381b033f975d32608f523561479a",
"assets/packages/reown_appkit/lib/modal/assets/account_disconnect.svg": "1e962e3b5c49f1066d059ee7607ca0fe",
"assets/packages/reown_appkit/lib/modal/assets/AppIcon.png": "b75e7478d25cba779922dd8ba50933f1",
"assets/packages/reown_appkit/lib/modal/assets/dark/all_wallets.svg": "4ece03ffb6d614fd85a4d6df5b108d44",
"assets/packages/reown_appkit/lib/modal/assets/dark/all_wallets_button.svg": "ade430bbada2c25a67ada7ad3fcc9443",
"assets/packages/reown_appkit/lib/modal/assets/dark/apple_logo.svg": "1c2e474924a90715809ec4465a3c3f2b",
"assets/packages/reown_appkit/lib/modal/assets/dark/code_button.svg": "50639a4921acf72c11feb41c0dadb773",
"assets/packages/reown_appkit/lib/modal/assets/dark/desktop_button.svg": "2b42d2f08591c8176ee81299c2010009",
"assets/packages/reown_appkit/lib/modal/assets/dark/discord_logo.svg": "c465c4650acbcee0a53311d60adee3c6",
"assets/packages/reown_appkit/lib/modal/assets/dark/extension_button.svg": "a1ebc16d3f6760e119bd0c436e724288",
"assets/packages/reown_appkit/lib/modal/assets/dark/facebook_logo.svg": "152a9c45f0e68feadd8f15c9e5b90d1c",
"assets/packages/reown_appkit/lib/modal/assets/dark/farcaster_logo.svg": "acd1b1ccb807757accc8d5f4cd863916",
"assets/packages/reown_appkit/lib/modal/assets/dark/github_logo.svg": "73ff262d9c42db3d76a03cb0530b56a4",
"assets/packages/reown_appkit/lib/modal/assets/dark/google_logo.svg": "8f89273afa59538fb75c3637cb66fb36",
"assets/packages/reown_appkit/lib/modal/assets/dark/input_cancel.svg": "66ea9f88351527973b7d22f22bcb86f7",
"assets/packages/reown_appkit/lib/modal/assets/dark/logo_walletconnect.svg": "1062455cf06aba4ef160f906514a28ef",
"assets/packages/reown_appkit/lib/modal/assets/dark/mobile_button.svg": "3062507bbc0b5d2a29c104f6dbd61629",
"assets/packages/reown_appkit/lib/modal/assets/dark/more_social_icon.svg": "27519472b2fd2375a4ff3d926bc750da",
"assets/packages/reown_appkit/lib/modal/assets/dark/qr_code.svg": "851d45bb010e5dfaa2f34f9cb62c5e7f",
"assets/packages/reown_appkit/lib/modal/assets/dark/qr_code_button.svg": "87923d03176199d48b9cd2f46568844a",
"assets/packages/reown_appkit/lib/modal/assets/dark/telegram_logo.svg": "240aa708d56f5800959a060dea927d32",
"assets/packages/reown_appkit/lib/modal/assets/dark/twitch_logo.svg": "6b6c187feefb56fd2e5cd121305d9a44",
"assets/packages/reown_appkit/lib/modal/assets/dark/web_button.svg": "61af2a36faadee5f62018fc59201cb11",
"assets/packages/reown_appkit/lib/modal/assets/dark/x_logo.svg": "f77987fc85a32dd7dee5e98789d6d8ab",
"assets/packages/reown_appkit/lib/modal/assets/help/chart.svg": "7ac5fd4b1fa05e6853229070fd380c89",
"assets/packages/reown_appkit/lib/modal/assets/help/compass.svg": "73f5b5773495c7b38034917e1108e310",
"assets/packages/reown_appkit/lib/modal/assets/help/dao.svg": "37bc884bb4c25c668e857a7b7c5b6adc",
"assets/packages/reown_appkit/lib/modal/assets/help/defi.svg": "82f1e28b6c5abe77773fef9aaf21e55a",
"assets/packages/reown_appkit/lib/modal/assets/help/eth.svg": "baf5ae21f167b4512c2f12be3dc032b0",
"assets/packages/reown_appkit/lib/modal/assets/help/key.svg": "3a19cb388cfc0747b9517c424aaecfe9",
"assets/packages/reown_appkit/lib/modal/assets/help/layers.svg": "e29d83814272f8b17db2e84eb62938a7",
"assets/packages/reown_appkit/lib/modal/assets/help/lock.svg": "3084e9137bc93199a6a9010f63757442",
"assets/packages/reown_appkit/lib/modal/assets/help/network.svg": "3f8bd92c1e4b1d766c361c113273faaa",
"assets/packages/reown_appkit/lib/modal/assets/help/noun.svg": "45ac2041d4e172746cefcb304c577bfc",
"assets/packages/reown_appkit/lib/modal/assets/help/painting.svg": "bc1f3af0e6e5c57f2e82ac74468fa31f",
"assets/packages/reown_appkit/lib/modal/assets/help/system.svg": "5653685e83efb0b3d45a38db575de9c8",
"assets/packages/reown_appkit/lib/modal/assets/help/user.svg": "ecb763fd28aa204a17594803b9313bf1",
"assets/packages/reown_appkit/lib/modal/assets/icons/arrow_bottom_circle.svg": "0daa03f172deac847f28add6dd4c86f4",
"assets/packages/reown_appkit/lib/modal/assets/icons/arrow_down.svg": "ab4be8382d7ef0399d5ad1371fa98a86",
"assets/packages/reown_appkit/lib/modal/assets/icons/arrow_top_right.svg": "f6ae3a7fcb83aa44bac69608b18cf500",
"assets/packages/reown_appkit/lib/modal/assets/icons/certified.svg": "6469a76b65b832e66b25b09f6a266df1",
"assets/packages/reown_appkit/lib/modal/assets/icons/checkmark.svg": "7c4ee5c9050caf592728a3fd650872ba",
"assets/packages/reown_appkit/lib/modal/assets/icons/chevron_down.svg": "04fd0c04bd23b4c4d0baa680abc4e3f7",
"assets/packages/reown_appkit/lib/modal/assets/icons/chevron_left.svg": "e258aa34911cfae14743343f7fa9f58b",
"assets/packages/reown_appkit/lib/modal/assets/icons/chevron_right.svg": "6d73c4dc08c1b29868670f285f90dc47",
"assets/packages/reown_appkit/lib/modal/assets/icons/close.svg": "54241b625497b2a264df8fccb7a8a649",
"assets/packages/reown_appkit/lib/modal/assets/icons/code.svg": "0e2acde8a0260f0b4597c69ba1d2976d",
"assets/packages/reown_appkit/lib/modal/assets/icons/coin.svg": "75eb1709228de3ba415b11b7d31c3c1f",
"assets/packages/reown_appkit/lib/modal/assets/icons/compass.svg": "96a71c0b2e8136482957120cc16f28fe",
"assets/packages/reown_appkit/lib/modal/assets/icons/copy.svg": "0b2aef8f77993bf3ef6ff979ec1dedf5",
"assets/packages/reown_appkit/lib/modal/assets/icons/copy_14.svg": "09ce7e33c714abc2bea05eef458d19a8",
"assets/packages/reown_appkit/lib/modal/assets/icons/disconnect.svg": "fe22360a30e0f2dfcc0166af27093bb0",
"assets/packages/reown_appkit/lib/modal/assets/icons/dots.svg": "4d9fa6466b92e51c7a53b37a451076eb",
"assets/packages/reown_appkit/lib/modal/assets/icons/extension.svg": "0f4fcd6cbe352c09eb9e151a2e0f6b06",
"assets/packages/reown_appkit/lib/modal/assets/icons/help.svg": "3c03bdbbd073a7556a837abf21c52fab",
"assets/packages/reown_appkit/lib/modal/assets/icons/info.svg": "8327eb5fda28136ea6bb96e2f9c28ca1",
"assets/packages/reown_appkit/lib/modal/assets/icons/mail.svg": "f3f5a34474ce2f5a91b4d46ae754fded",
"assets/packages/reown_appkit/lib/modal/assets/icons/mobile.svg": "52e74ac4af896a985dfda155f7bb14f3",
"assets/packages/reown_appkit/lib/modal/assets/icons/network.svg": "26be13d1280d5b1f9a11324a78ca8afa",
"assets/packages/reown_appkit/lib/modal/assets/icons/nft.svg": "b274b21234179416ee10a9f6b638e944",
"assets/packages/reown_appkit/lib/modal/assets/icons/paperplane.svg": "5517102d3b01dffe29e8e97126a52d06",
"assets/packages/reown_appkit/lib/modal/assets/icons/receive.svg": "ab4be8382d7ef0399d5ad1371fa98a86",
"assets/packages/reown_appkit/lib/modal/assets/icons/refresh.svg": "65e23c2043fc03c67660d4b846236624",
"assets/packages/reown_appkit/lib/modal/assets/icons/refresh_back.svg": "c856132e8c52d9c6dd35eb9d43cbd389",
"assets/packages/reown_appkit/lib/modal/assets/icons/regular/receive.svg": "0002f406e2e70cc2a1360a38686059d0",
"assets/packages/reown_appkit/lib/modal/assets/icons/regular/send.svg": "d7a7de8320b40ab4836e75c2daf748cb",
"assets/packages/reown_appkit/lib/modal/assets/icons/regular/swap.svg": "fe8ae364779b6766face3fd2344f9847",
"assets/packages/reown_appkit/lib/modal/assets/icons/regular/wallet.svg": "933136188af50bf74e5b7ee0786c336e",
"assets/packages/reown_appkit/lib/modal/assets/icons/search.svg": "bbdea538979fc2e7a8a8538f67b0541a",
"assets/packages/reown_appkit/lib/modal/assets/icons/send.svg": "57212030b11606ca914343f9f06c0c98",
"assets/packages/reown_appkit/lib/modal/assets/icons/swap_horizontal.svg": "c4c6b9a3c8a4eb638b6171a83e977a6c",
"assets/packages/reown_appkit/lib/modal/assets/icons/swap_vertical.svg": "407524d4debfc341651982f71696db70",
"assets/packages/reown_appkit/lib/modal/assets/icons/verif.svg": "d757b559a33476394f77c593527a1b34",
"assets/packages/reown_appkit/lib/modal/assets/icons/wallet.svg": "bac0bd06bc142c95b1b68ed306b1187c",
"assets/packages/reown_appkit/lib/modal/assets/icons/warning.svg": "2a11047bfb7f2ef43cd4535aa8511461",
"assets/packages/reown_appkit/lib/modal/assets/icons/wc.svg": "5d82c10b49486cdb55a67bacb36633e0",
"assets/packages/reown_appkit/lib/modal/assets/light/all_wallets.svg": "c1df4d56d2564aa3ccf28931ac51e916",
"assets/packages/reown_appkit/lib/modal/assets/light/all_wallets_button.svg": "34bd234b88d68986952d7f4e0cf65444",
"assets/packages/reown_appkit/lib/modal/assets/light/apple_logo.svg": "1c2e474924a90715809ec4465a3c3f2b",
"assets/packages/reown_appkit/lib/modal/assets/light/code_button.svg": "c39b1088176e162b5879bb9bcb3a49f1",
"assets/packages/reown_appkit/lib/modal/assets/light/desktop_button.svg": "6cb02d5b2d4fe40c173337d8183dd5ea",
"assets/packages/reown_appkit/lib/modal/assets/light/discord_logo.svg": "c465c4650acbcee0a53311d60adee3c6",
"assets/packages/reown_appkit/lib/modal/assets/light/extension_button.svg": "c9d917766350916bd48e7dac6ea255dc",
"assets/packages/reown_appkit/lib/modal/assets/light/facebook_logo.svg": "152a9c45f0e68feadd8f15c9e5b90d1c",
"assets/packages/reown_appkit/lib/modal/assets/light/farcaster_logo.svg": "acd1b1ccb807757accc8d5f4cd863916",
"assets/packages/reown_appkit/lib/modal/assets/light/github_logo.svg": "73ff262d9c42db3d76a03cb0530b56a4",
"assets/packages/reown_appkit/lib/modal/assets/light/google_logo.svg": "8f89273afa59538fb75c3637cb66fb36",
"assets/packages/reown_appkit/lib/modal/assets/light/input_cancel.svg": "f0a69929f42f8bce6b80ca38f0c723b8",
"assets/packages/reown_appkit/lib/modal/assets/light/logo_walletconnect.svg": "b7f6821ccd5d4b805b5dc6cc98a802f1",
"assets/packages/reown_appkit/lib/modal/assets/light/mobile_button.svg": "1a6d5978f470e5e56c93cd2602e86a2c",
"assets/packages/reown_appkit/lib/modal/assets/light/more_social_icon.svg": "c01a387a26eeabe13e8cc5115a99d6f2",
"assets/packages/reown_appkit/lib/modal/assets/light/qr_code.svg": "86e507bc2c166ffaa096de2a0f3dbe67",
"assets/packages/reown_appkit/lib/modal/assets/light/qr_code_button.svg": "3f46784373248b623cbb9d569044f291",
"assets/packages/reown_appkit/lib/modal/assets/light/telegram_logo.svg": "240aa708d56f5800959a060dea927d32",
"assets/packages/reown_appkit/lib/modal/assets/light/twitch_logo.svg": "6b6c187feefb56fd2e5cd121305d9a44",
"assets/packages/reown_appkit/lib/modal/assets/light/web_button.svg": "063a5bb2f31eba3e1291a5dbbb4b4e88",
"assets/packages/reown_appkit/lib/modal/assets/light/x_logo.svg": "f77987fc85a32dd7dee5e98789d6d8ab",
"assets/packages/reown_appkit/lib/modal/assets/network_placeholder.svg": "68f2b0a1756952f2f1dd75558b98a1de",
"assets/packages/reown_appkit/lib/modal/assets/png/2.0x/app_store.png": "9a63bdbc92a38638edeaedc32fe093d8",
"assets/packages/reown_appkit/lib/modal/assets/png/2.0x/farcaster.png": "0cbc4d47af62f9c09c35fd27a376a7fc",
"assets/packages/reown_appkit/lib/modal/assets/png/2.0x/google_play.png": "6d9be20a67d8b99d04bbf688973b6c6e",
"assets/packages/reown_appkit/lib/modal/assets/png/2.0x/logo_wc.png": "e73ddf9aae5dc9f2a6668e45ad4bde69",
"assets/packages/reown_appkit/lib/modal/assets/png/3.0x/app_store.png": "aed9e5fcb620e705831ccda22a853031",
"assets/packages/reown_appkit/lib/modal/assets/png/3.0x/farcaster.png": "583c2e0eb0ee88718b67aa8a86d9ab88",
"assets/packages/reown_appkit/lib/modal/assets/png/3.0x/google_play.png": "6d8da1b598c096f5a81e3d911c8ca4dd",
"assets/packages/reown_appkit/lib/modal/assets/png/3.0x/logo_wc.png": "2a597146116d0d5181e904b0c9264fdc",
"assets/packages/reown_appkit/lib/modal/assets/png/app_store.png": "dd9fdf8975a6f9cf988d0871d5411f60",
"assets/packages/reown_appkit/lib/modal/assets/png/farcaster.png": "39246cdc66e93104efb35490b639355e",
"assets/packages/reown_appkit/lib/modal/assets/png/google_play.png": "cdbe574f3e9b36cf8ee5be25a630ecf0",
"assets/packages/reown_appkit/lib/modal/assets/png/logo_wc.png": "e73ddf9aae5dc9f2a6668e45ad4bde69",
"assets/packages/reown_appkit/lib/modal/assets/token_placeholder.svg": "3a5862d4c9d5079be33d55691e730ae2",
"assets/packages/reown_appkit/lib/modal/assets/wallet_flutter.png": "d255167a856a35b62c94d6b66506b2d4",
"assets/packages/reown_appkit/lib/modal/assets/wallet_kotlin.png": "ed657a704fdbd919e8652cc7885dbe03",
"assets/packages/reown_appkit/lib/modal/assets/wallet_placeholder.svg": "1a9b45ad3b851a6cc7193ee61808aa7e",
"assets/packages/reown_appkit/lib/modal/assets/wallet_react.png": "e5978006d3692d182c8855feea80b5e4",
"assets/packages/reown_appkit/lib/modal/assets/wallet_react_native.png": "7f0e071d4bd9556284fb64ba1ebaf8e0",
"assets/packages/reown_appkit/lib/modal/assets/wallet_swift.png": "eaa6ae7054430bfeab1d1f50a16a5a51",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "d362ab962b2af3980f0448de9788c436",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "3d7204def7cfec051c06084f2d427aa2",
"/": "3d7204def7cfec051c06084f2d427aa2",
"main.dart.js": "690a89852cdcb2a9ff32cdf6ff8632ab",
"manifest.json": "a400dcc72eb82d385b43bbc3b36ff510",
"version.json": "f7f9f25ad9b1b8b6807aa2989bdfa62f"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
