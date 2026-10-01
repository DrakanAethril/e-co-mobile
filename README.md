# e-CO

Mobile app (Flutter) for e-CO, the orienteering-race module of
[moncampus](https://github.com/DrakanAethril/moncampus).

## Web version (PWA)

The same app also builds for the browser, served by moncampus at `/eco-app/` - the way onto an
iPhone while no IPA can be signed. `tool/build_pwa.sh` builds it and copies it into moncampus's
`public/eco-app/`; never pass it `API_BASE_URL`, the PWA talks to the origin that serves it.

Only the platform layer differs (`web/`): the offline queue lives in IndexedDB (`web/eco_queue.js`)
and is sent by the same `QueueProcessor` as on the phone, and the service worker (`web/eco_sw.js`)
keeps the app openable offline and sends the queue by background sync when the page is frozen or
closed - Chrome on Android only, Safari has no background sync.

## License

Copyright (c) 2026 Sébastien Tharaud. Released under the **MIT License** — see [LICENSE](LICENSE).

The licence differs from the MonCampus server, which is AGPL-3.0-or-later: this repository is a thin
client distributed through app stores, and Apple's App Store terms are widely held to be incompatible
with the GPL family. It should stay permissively licensed.

Institution Beaupeyrat's names and logos are not covered by the licence, and the bundled fonts carry
their own SIL Open Font License — see [NOTICE](NOTICE).

> **Maps.** Tiles come from OpenStreetMap, so every map must display the "© OpenStreetMap
> contributors" credit — a condition of the ODbL, not a courtesy. Use the shared `EcoMapAttribution`
> widget (`lib/widgets/eco_widgets.dart`) on any new map screen. The app also fetches tiles straight
> from OpenStreetMap's own servers, which their Tile Usage Policy reserves for modest traffic; a
> dedicated tile provider is the right answer for sustained production use — see [NOTICE](NOTICE).
