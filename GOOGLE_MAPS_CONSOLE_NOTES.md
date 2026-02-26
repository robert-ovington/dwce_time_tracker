# Google Maps – Console messages (web)

When the app loads the Google Maps JavaScript API on web, you may see these messages. Here is what they mean and what the project does about them.

---

## 1. “Google Maps JavaScript API has been loaded directly without loading=async”

**Meaning:** Google recommends loading the Maps API with the `loading=async` parameter and then using `google.maps.importLibrary()` instead of the classic, synchronous API.

**Why we don’t change it:** The Flutter web plugin (`google_maps_flutter_web`) is built for the classic API and expects `google.maps` to be available as soon as the script loads. Switching to `loading=async` would require the plugin to use `importLibrary()`, which it does not do yet. So we keep loading the script without `loading=async` to avoid breaking the map.

**What we do:** The script is loaded with `async` and `defer` on the `<script>` tag, and we only inject it when a screen needs the map. So loading is already non-blocking from the page’s point of view.

---

## 2. “google.maps.Marker is deprecated. Please use google.maps.marker.AdvancedMarkerElement”

**Meaning:** As of February 2024, the Maps JavaScript API deprecates `google.maps.Marker` in favour of `google.maps.marker.AdvancedMarkerElement`. The old class still works and will get critical fixes; Google will give at least 12 months’ notice before discontinuing it.

**Why it appears:** The app uses the Flutter type `Marker` from `package:google_maps_flutter`. On web, the plugin’s implementation (`google_maps_flutter_web`) uses the deprecated `google.maps.Marker` under the hood. The deprecation warning is emitted by the Maps API when that code runs, not by our Dart code directly.

**What we do:** We cannot replace `Marker` with `AdvancedMarkerElement` inside our app code, because the creation of the JS marker happens inside the Flutter plugin. We have added `libraries=marker` to the Maps script URL in `web/index.html` so the marker library (including `AdvancedMarkerElement`) is loaded. When `google_maps_flutter_web` adds support for advanced markers, no change to the script URL should be needed.

**If you want to track plugin support:** See the Flutter/plugin issue [flutter/flutter#144151](https://github.com/flutter/flutter/issues/144151) and the [Maps Advanced Markers migration guide](https://developers.google.com/maps/documentation/javascript/advanced-markers/migration).

---

## Summary

| Message | Cause | Action in this project |
|--------|--------|-------------------------|
| Loaded without `loading=async` | We use classic script load for plugin compatibility | Documented; no change so the map keeps working. |
| `Marker` deprecated | Plugin uses `google.maps.Marker` on web | Documented; added `libraries=marker`; migration depends on plugin update. |
