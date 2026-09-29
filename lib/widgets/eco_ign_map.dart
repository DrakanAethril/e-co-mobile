import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// The IGN's Géoplateforme in the Web-Mercator tile grid flutter_map already speaks: `{z}/{y}/{x}`
/// of an ordinary tile URL are WMTS's TILEMATRIX/TILEROW/TILECOL. No key, and no rate limit on
/// WMTS. Mirrors assets/controllers/eco_map.js on the web side, so both show the same four layers.
const String _ignWmts = 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
    '&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

/// Two base maps, one at a time: the Plan IGN reads paths and place names, the aerial photograph
/// reads clearings, edges and undergrowth.
enum EcoMapBase {
  plan('Plan IGN', 'GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2', 'image/png'),
  photo('Photographies aériennes', 'ORTHOIMAGERY.ORTHOPHOTOS', 'image/jpeg');

  final String label;
  final String layer;
  final String format;
  const EcoMapBase(this.label, this.layer, this.format);
}

/// Laid over either base map: the contour lines are the relief of an orienteering map, the LiDAR
/// HD shading shows the banks, ditches and gullies a 1:25 000 map smooths away.
enum EcoMapOverlay {
  contours('Courbes de niveau', 'ELEVATION.CONTOUR.LINE', 1.0),
  relief('Relief LiDAR HD', 'IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW', 0.4);

  final String label;
  final String layer;

  /// The shading is opaque grey: drawn at full strength it would hide the base map.
  final double opacity;
  const EcoMapOverlay(this.label, this.layer, this.opacity);
}

/// Every e-CO map: the IGN layers the user last chose, the markers the screen hands in, the credit
/// and the layer button. [attributionTrailing] is passed through to [EcoMapAttribution].
class EcoIgnMap extends StatefulWidget {
  final MapOptions options;
  final List<Widget> children;
  final String? attributionTrailing;

  const EcoIgnMap({
    super.key,
    required this.options,
    required this.children,
    this.attributionTrailing,
  });

  @override
  State<EcoIgnMap> createState() => _EcoIgnMapState();
}

class _EcoIgnMapState extends State<EcoIgnMap> {
  static const _baseKey = 'eco_map_base';

  /// A tile that does not load is a blank square on the map, and that square is the whole signal:
  /// out of coverage in a wood, the phone would otherwise report every missing tile as an error
  /// nobody reads.
  static final _tiles = NetworkTileProvider(silenceExceptions: true);
  static const _overlaysKey = 'eco_map_overlays';

  EcoMapBase _base = EcoMapBase.plan;
  Set<EcoMapOverlay> _overlays = {};

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// The layers are a convenience remembered on the phone: without it the map opens on the Plan.
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final base = EcoMapBase.values.where((b) => b.name == prefs.getString(_baseKey)).firstOrNull;
    final overlays = (prefs.getStringList(_overlaysKey) ?? [])
        .map((name) => EcoMapOverlay.values.where((o) => o.name == name).firstOrNull)
        .whereType<EcoMapOverlay>()
        .toSet();

    if (!mounted) {
      return;
    }
    setState(() {
      _base = base ?? EcoMapBase.plan;
      _overlays = overlays;
    });
  }

  Future<void> _store() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseKey, _base.name);
    await prefs.setStringList(_overlaysKey, _overlays.map((o) => o.name).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          options: widget.options,
          children: [
            TileLayer(
              urlTemplate: '$_ignWmts&LAYER=${_base.layer}&FORMAT=${_base.format}',
              userAgentPackageName: 'com.beaupeyrat.eco',
              maxNativeZoom: 19,
              tileProvider: _tiles,
            ),
            for (final overlay in EcoMapOverlay.values.where(_overlays.contains))
              Opacity(
                opacity: overlay.opacity,
                child: TileLayer(
                  urlTemplate: '$_ignWmts&LAYER=${overlay.layer}&FORMAT=image/png',
                  userAgentPackageName: 'com.beaupeyrat.eco',
                  maxNativeZoom: 18,
                  tileProvider: _tiles,
                  // The overlays are transparent PNGs laid on a base map already on screen: no
                  // point fading them in over a blank.
                  tileDisplay: const TileDisplay.instantaneous(),
                ),
              ),
            ...widget.children,
          ],
        ),
        EcoMapAttribution(trailing: widget.attributionTrailing),
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Material(
              color: Colors.white.withOpacity(0.94),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: EcoColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openPicker,
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(Icons.layers_outlined, size: 20, color: EcoColors.blueDark),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
            _store();
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetTitle('Fond de carte'),
                  for (final base in EcoMapBase.values)
                    RadioListTile<EcoMapBase>(
                      value: base,
                      groupValue: _base,
                      activeColor: EcoColors.blue,
                      dense: true,
                      title: Text(base.label, style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: EcoColors.ink)),
                      onChanged: (value) => update(() => _base = value ?? _base),
                    ),
                  const SizedBox(height: 6),
                  _sheetTitle('Superposer'),
                  for (final overlay in EcoMapOverlay.values)
                    CheckboxListTile(
                      value: _overlays.contains(overlay),
                      activeColor: EcoColors.blue,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(overlay.label, style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: EcoColors.ink)),
                      onChanged: (checked) => update(() {
                        _overlays = {..._overlays};
                        checked == true ? _overlays.add(overlay) : _overlays.remove(overlay);
                      }),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: EcoFont.sans(size: 11, weight: FontWeight.w700, color: EcoColors.faint),
      ),
    );
  }
}

/// The IGN credit that must sit on top of every map.
///
/// This is a licence obligation, not decoration: the tiles come from the IGN's Géoplateforme,
/// published under the Licence Ouverte (Etalab 2.0), whose one condition is that the source is
/// named wherever the map is shown. [EcoIgnMap] draws it; keep it on any map built another way.
/// [trailing] appends a screen-specific detail after a middot (the live-tracking screen uses it for
/// its refresh cadence) without displacing the credit itself.
class EcoMapAttribution extends StatelessWidget {
  final String? trailing;
  final Alignment alignment;

  const EcoMapAttribution({
    super.key,
    this.trailing,
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final label = trailing == null ? '© IGN – Géoplateforme' : '© IGN – Géoplateforme · $trailing';

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            border: Border.all(color: EcoColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: EcoFont.sans(size: 9.5, weight: FontWeight.w600, color: EcoColors.faint),
          ),
        ),
      ),
    );
  }
}
