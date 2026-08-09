# e-CO

Mobile app (Flutter) for e-CO, the orienteering-race module of
[moncampus](https://github.com/DrakanAethril/moncampus).

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
