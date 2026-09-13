import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SubtitleTarget { text, border, shadow, background }

class SubtitleStudioSheet extends StatefulWidget {
  final Map<String, dynamic> initialStyle;
  final Function(Map<String, dynamic>) onStyleChanged;

  const SubtitleStudioSheet({
    super.key,
    required this.initialStyle,
    required this.onStyleChanged,
  });

  @override
  State<SubtitleStudioSheet> createState() => _SubtitleStudioSheetState();
}

class _SubtitleStudioSheetState extends State<SubtitleStudioSheet> {
  // Local state mirrored from widget.initialStyle
  late Color _subTextColor;
  late double _subTextAlpha;
  late double _subFontSize;
  late FontWeight _subFontWeight;
  late double _subLetterSpacing;
  late String _subFontFamily;
  late bool _subAllCaps;
  late bool _subItalic;
  late Color _subBorderColor;
  late double _subBorderAlpha;
  late double _subBorderSize;
  late Color _subShadowColor;
  late double _subShadowAlpha;
  late double _shadowDistance;
  late double _shadowAngle;
  late double _shadowBlur;
  late Color _subBoxColor;
  late double _subBoxAlpha;
  late double _subBoxPaddingH;
  late double _subBoxPaddingV;
  late double _subBoxRadius;
  late double _subPositionOffset;
  late bool _overrideAss;
  late int _subAlign;
  String? _subFontPath;

  SubtitleTarget _activeTarget = SubtitleTarget.text;
  Map<String, Map<String, dynamic>> _userPresets = {};

  @override
  void initState() {
    super.initState();
    _applyStyleMap(widget.initialStyle, notify: false);
    _loadUserPresets();
  }

  void _applyStyleMap(Map<String, dynamic> style, {bool notify = true}) {
    _subTextColor = Color(style['textColor'] ?? Colors.white.toARGB32());
    _subTextAlpha = (style['textAlpha'] ?? 1.0).toDouble();
    _subBorderColor = Color(style['borderColor'] ?? Colors.black.toARGB32());
    _subBorderAlpha = (style['borderAlpha'] ?? 1.0).toDouble();
    _subShadowColor = Color(style['shadowColor'] ?? Colors.black.toARGB32());
    _subShadowAlpha = (style['shadowAlpha'] ?? 0.8).toDouble();
    _subBoxColor = Color(style['boxColor'] ?? Colors.black.toARGB32());
    _subBoxAlpha = (style['boxAlpha'] ?? 0.0).toDouble();
    _subBorderSize = (style['borderSize'] ?? 2.5).toDouble();
    _shadowDistance = (style['shadowDistance'] ?? 3.0).toDouble();
    _shadowAngle = (style['shadowAngle'] ?? 45.0).toDouble();
    _shadowBlur = (style['shadowBlur'] ?? 2.0).toDouble();
    _subBoxPaddingH = (style['boxPaddingH'] ?? 8.0).toDouble();
    _subBoxPaddingV = (style['boxPaddingV'] ?? 4.0).toDouble();
    _subBoxRadius = (style['boxRadius'] ?? 6.0).toDouble();
    _subFontWeight = FontWeight.values.firstWhere((w) => w.value == (style['fontWeight'] ?? 600), orElse: () => FontWeight.w600);
    _subLetterSpacing = (style['letterSpacing'] ?? 0.5).toDouble();
    _subFontFamily = style['fontFamily'] ?? 'Roboto';
    _subAllCaps = style['allCaps'] ?? false;
    _subItalic = style['italic'] ?? false;
    _subFontSize = (style['fontSize'] ?? 24.0).toDouble();
    _subFontPath = style['fontPath'];
    _subPositionOffset = (style['positionOffset'] ?? 20.0).toDouble();
    _subAlign = style['align'] ?? 1;
    _overrideAss = style['overrideAss'] ?? true;

    if (notify) {
      _notifyChanges();
    }
  }

  void _notifyChanges() {
    widget.onStyleChanged({
      'textColor': _subTextColor.toARGB32(),
      'textAlpha': _subTextAlpha,
      'borderColor': _subBorderColor.toARGB32(),
      'borderAlpha': _subBorderAlpha,
      'shadowColor': _subShadowColor.toARGB32(),
      'shadowAlpha': _subShadowAlpha,
      'boxColor': _subBoxColor.toARGB32(),
      'boxAlpha': _subBoxAlpha,
      'borderSize': _subBorderSize,
      'shadowDistance': _shadowDistance,
      'shadowAngle': _shadowAngle,
      'shadowBlur': _shadowBlur,
      'boxPaddingH': _subBoxPaddingH,
      'boxPaddingV': _subBoxPaddingV,
      'boxRadius': _subBoxRadius,
      'fontWeight': _subFontWeight.value,
      'letterSpacing': _subLetterSpacing,
      'fontFamily': _subFontFamily,
      'allCaps': _subAllCaps,
      'italic': _subItalic,
      'fontSize': _subFontSize,
      'fontPath': _subFontPath,
      'positionOffset': _subPositionOffset,
      'align': _subAlign,
      'overrideAss': _overrideAss,
    });
  }

  Future<void> _loadUserPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('custom_subtitle_presets');
    if (raw != null) {
      setState(() {
        _userPresets = Map<String, Map<String, dynamic>>.from(jsonDecode(raw));
      });
    }
  }

  Future<void> _saveUserPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final style = {
      'name': name,
      'textColor': _subTextColor.toARGB32(),
      'textAlpha': _subTextAlpha,
      'borderColor': _subBorderColor.toARGB32(),
      'borderAlpha': _subBorderAlpha,
      'shadowColor': _subShadowColor.toARGB32(),
      'shadowAlpha': _subShadowAlpha,
      'boxColor': _subBoxColor.toARGB32(),
      'boxAlpha': _subBoxAlpha,
      'borderSize': _subBorderSize,
      'shadowDistance': _shadowDistance,
      'shadowAngle': _shadowAngle,
      'shadowBlur': _shadowBlur,
      'boxPaddingH': _subBoxPaddingH,
      'boxPaddingV': _subBoxPaddingV,
      'boxRadius': _subBoxRadius,
      'fontWeight': _subFontWeight.value,
      'letterSpacing': _subLetterSpacing,
      'fontFamily': _subFontFamily,
      'allCaps': _subAllCaps,
      'italic': _subItalic,
      'fontSize': _subFontSize,
      'fontPath': _subFontPath,
      'positionOffset': _subPositionOffset,
      'align': _subAlign,
      'overrideAss': _overrideAss,
    };
    _userPresets[name] = style;
    await prefs.setString('custom_subtitle_presets', jsonEncode(_userPresets));
    _loadUserPresets();
  }

  Future<void> _deleteUserPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    _userPresets.remove(name);
    await prefs.setString('custom_subtitle_presets', jsonEncode(_userPresets));
    _loadUserPresets();
  }

  static final Map<String, Map<String, dynamic>> _defaultSubPresets = {
    'Netflix Classic': {
      'textColor': Colors.white.toARGB32(),
      'textAlpha': 1.0,
      'borderColor': Colors.black.toARGB32(),
      'borderAlpha': 1.0,
      'shadowColor': Colors.black.toARGB32(),
      'shadowAlpha': 0.5,
      'borderSize': 2.0,
      'shadowDistance': 2.5,
      'shadowAngle': 45.0,
      'shadowBlur': 1.0,
      'fontSize': 24.0,
      'fontWeight': 600,
    },
    'Anime Gold': {
      'textColor': 0xFFFFD700,
      'textAlpha': 1.0,
      'borderColor': 0xFF000000,
      'borderAlpha': 1.0,
      'borderSize': 3.5,
      'shadowAlpha': 0.0,
      'fontSize': 28.0,
      'fontWeight': 900,
    },
    'Cyber Neon': {
      'textColor': 0xFF00FFFF,
      'textAlpha': 1.0,
      'borderColor': 0xFFFF00FF,
      'borderAlpha': 0.8,
      'borderSize': 1.5,
      'shadowColor': 0xFFFF00FF,
      'shadowAlpha': 1.0,
      'shadowBlur': 10.0,
      'fontSize': 24.0,
    },
    'High Contrast Box': {
      'textColor': 0xFFFFFF00,
      'textAlpha': 1.0,
      'boxColor': 0xFF000000,
      'boxAlpha': 0.85,
      'boxRadius': 4.0,
      'boxPaddingH': 12.0,
      'boxPaddingV': 6.0,
      'fontSize': 22.0,
      'borderSize': 0.0,
    },
  };

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return DefaultTabController(
      length: 5,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.95),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 8),
                    const Text('Subtitle Studio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              // Scrollable Top Section (Preview + Color Hub)
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildSubtitlePreview(isLandscape),
                    _buildColorStudioHub(),
                  ],
                ),
              ),

              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorColor: Colors.redAccent,
                labelColor: Colors.redAccent,
                unselectedLabelColor: Colors.white54,
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                padding: EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  Tab(text: 'Text'),
                  Tab(text: 'Border'),
                  Tab(text: 'Shadow'),
                  Tab(text: 'Box'),
                  Tab(text: 'Global'),
                ],
              ),

              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildTypographyTab(),
                    _buildBorderTab(),
                    _buildShadowTab(),
                    _buildBackgroundTab(),
                    _buildGlobalTab(),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitlePreview(bool isLandscape) {
    return Container(
      width: double.infinity,
      height: isLandscape ? 60 : 90,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Text(
          "Sample Subtitle Preview",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _subTextColor.withValues(alpha: _subTextAlpha),
            fontSize: isLandscape ? 18 : 22,
            fontWeight: _subFontWeight,
            fontStyle: _subItalic ? FontStyle.italic : FontStyle.normal,
            fontFamily: _subFontFamily,
            letterSpacing: _subLetterSpacing,
            shadows: [
              if (_shadowDistance > 0 || _shadowBlur > 0)
                Shadow(
                  color: _subShadowColor.withValues(alpha: _subShadowAlpha),
                  offset: Offset(_shadowDistance, _shadowDistance), // Simplified for preview
                  blurRadius: _shadowBlur,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorStudioHub() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTargetCard(SubtitleTarget.text, 'T', 'Text', _subTextColor, _subTextAlpha),
              _buildTargetCard(SubtitleTarget.border, '▢', 'Border', _subBorderColor, _subBorderAlpha),
              _buildTargetCard(SubtitleTarget.shadow, '◐', 'Shadow', _subShadowColor, _subShadowAlpha),
              _buildTargetCard(SubtitleTarget.background, '▨', 'Box', _subBoxColor, _subBoxAlpha),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: ColorPicker(
                  pickerColor: _getCurrentTargetColor().withValues(alpha: 1.0),
                  onColorChanged: (newColor) {
                    setState(() {
                      _updateTargetColor(newColor);
                    });
                  },
                  colorPickerWidth: 140,
                  pickerAreaHeightPercent: 0.7,
                  enableAlpha: false,
                  displayThumbColor: true,
                  paletteType: PaletteType.hueWheel,
                  labelTypes: const [],
                  pickerAreaBorderRadius: BorderRadius.circular(70),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildColorDashboard()),
            ],
          ),
          const SizedBox(height: 8),
          _buildAlphaSlider(),
        ],
      ),
    );
  }

  Widget _buildTargetCard(SubtitleTarget target, String icon, String label, Color color, double alpha) {
    final isSelected = _activeTarget == target;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTarget = target;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.redAccent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(icon, style: TextStyle(fontSize: 14, color: isSelected ? Colors.redAccent : Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: alpha),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 9, color: isSelected ? Colors.white : Colors.white38, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorDashboard() {
    final color = _getCurrentTargetColor();
    final alpha = _getCurrentTargetAlpha();
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final hsl = HSLColor.fromColor(color);

    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              if (alpha > 0.1) BoxShadow(color: color.withValues(alpha: alpha * 0.5), blurRadius: 8)
            ],
          ),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
            child: Text('HEX: $hex', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
          ),
        ),
        const SizedBox(height: 8),
        _buildValueLabel('RGB', '$r, $g, $b'),
        _buildValueLabel('HSL', '${hsl.hue.round()}°, ${(hsl.saturation * 100).round()}%, ${(hsl.lightness * 100).round()}%'),
        _buildValueLabel('Alpha', '${(alpha * 100).round()}%'),
      ],
    );
  }

  Widget _buildValueLabel(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 9, color: Colors.white38),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildAlphaSlider() {
    final color = _getCurrentTargetColor();
    final alpha = _getCurrentTargetAlpha();

    return Row(
      children: [
        const Icon(Icons.opacity, size: 14, color: Colors.white38),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: color,
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: alpha,
              min: 0,
              max: 1,
              onChanged: (v) {
                setState(() {
                  _updateTargetAlpha(v);
                });
              },
            ),
          ),
        ),
        Text('${(alpha * 100).round()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent, fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }

  Color _getCurrentTargetColor() {
    switch (_activeTarget) {
      case SubtitleTarget.text: return _subTextColor;
      case SubtitleTarget.border: return _subBorderColor;
      case SubtitleTarget.shadow: return _subShadowColor;
      case SubtitleTarget.background: return _subBoxColor;
    }
  }

  double _getCurrentTargetAlpha() {
    switch (_activeTarget) {
      case SubtitleTarget.text: return _subTextAlpha;
      case SubtitleTarget.border: return _subBorderAlpha;
      case SubtitleTarget.shadow: return _subShadowAlpha;
      case SubtitleTarget.background: return _subBoxAlpha;
    }
  }

  void _updateTargetColor(Color color) {
    switch (_activeTarget) {
      case SubtitleTarget.text: _subTextColor = color; break;
      case SubtitleTarget.border: _subBorderColor = color; break;
      case SubtitleTarget.shadow: _subShadowColor = color; break;
      case SubtitleTarget.background: _subBoxColor = color; break;
    }
    _notifyChanges();
  }

  void _updateTargetAlpha(double alpha) {
    switch (_activeTarget) {
      case SubtitleTarget.text: _subTextAlpha = alpha; break;
      case SubtitleTarget.border: _subBorderAlpha = alpha; break;
      case SubtitleTarget.shadow: _subShadowAlpha = alpha; break;
      case SubtitleTarget.background: _subBoxAlpha = alpha; break;
    }
    _notifyChanges();
  }

  Widget _buildTypographyTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: Text('Font Family', style: TextStyle(fontSize: 12, color: Colors.white70))),
            DropdownButton<String>(
              value: _subFontFamily,
              dropdownColor: const Color(0xFF1E1E1E),
              underline: const SizedBox(),
              items: ['Roboto', 'OpenSans', 'Montserrat', 'Inter', 'BebasNeue'].map((f) => DropdownMenuItem(
                value: f,
                child: Text(f, style: const TextStyle(fontSize: 12)),
              )).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _subFontFamily = v;
                    _notifyChanges();
                  });
                }
              },
            ),
          ],
        ),
        _buildSlider('Font Size', _subFontSize, 10, 80, (v) {
          setState(() {
            _subFontSize = v;
            _notifyChanges();
          });
        }),
        _buildSlider('Letter Spacing', _subLetterSpacing, -2, 10, (v) {
          setState(() {
            _subLetterSpacing = v;
            _notifyChanges();
          });
        }),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: Text('Font Weight', style: TextStyle(fontSize: 12, color: Colors.white70))),
            DropdownButton<FontWeight>(
              value: _subFontWeight,
              dropdownColor: const Color(0xFF1E1E1E),
              underline: const SizedBox(),
              items: [
                FontWeight.w300, FontWeight.w400, FontWeight.w500,
                FontWeight.w600, FontWeight.w700, FontWeight.w900,
              ].map((w) => DropdownMenuItem(
                value: w,
                child: Text('W${w.value}', style: const TextStyle(fontSize: 12)),
              )).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _subFontWeight = v;
                    _notifyChanges();
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _tabToggleButton('ITALIC', _subItalic, (v) {
              setState(() {
                _subItalic = v;
                _notifyChanges();
              });
            }),
            const SizedBox(width: 12),
            _tabToggleButton('ALL CAPS', _subAllCaps, (v) {
              setState(() {
                _subAllCaps = v;
                _notifyChanges();
              });
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildBorderTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSlider('Thickness', _subBorderSize, 0, 8.0, (v) {
          setState(() {
            _subBorderSize = v;
            _notifyChanges();
          });
        }),
      ],
    );
  }

  Widget _buildShadowTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSlider('Distance', _shadowDistance, 0, 20, (v) {
          setState(() {
            _shadowDistance = v;
            _notifyChanges();
          });
        }),
        _buildSlider('Angle', _shadowAngle, 0, 360, (v) {
          setState(() {
            _shadowAngle = v;
            _notifyChanges();
          });
        }),
        _buildSlider('Blur', _shadowBlur, 0, 12, (v) {
          setState(() {
            _shadowBlur = v;
            _notifyChanges();
          });
        }),
      ],
    );
  }

  Widget _buildBackgroundTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSlider('Padding H', _subBoxPaddingH, 0, 40, (v) {
          setState(() {
            _subBoxPaddingH = v;
            _notifyChanges();
          });
        }),
        _buildSlider('Padding V', _subBoxPaddingV, 0, 30, (v) {
          setState(() {
            _subBoxPaddingV = v;
            _notifyChanges();
          });
        }),
        _buildSlider('Radius', _subBoxRadius, 0, 24, (v) {
          setState(() {
            _subBoxRadius = v;
            _notifyChanges();
          });
        }),
      ],
    );
  }

  Widget _buildGlobalTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Presets', style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              ActionChip(
                avatar: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Save Current', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.white10,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () async {
                  final nameController = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      title: const Text('Save Preset', style: TextStyle(color: Colors.white)),
                      content: TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: 'Preset Name', hintStyle: TextStyle(color: Colors.white24)),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Save')),
                      ],
                    ),
                  );
                  if (name != null && name.isNotEmpty) {
                    await _saveUserPreset(name);
                  }
                },
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                label: const Text('Reset', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.white10,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () {
                  setState(() {
                    _applyStyleMap(_defaultSubPresets['Netflix Classic']!);
                  });
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: VerticalDivider(width: 1, indent: 8, endIndent: 8, color: Colors.white24),
              ),
              ..._defaultSubPresets.keys.map((name) => _subPresetChip(name, () {
                setState(() {
                  _applyStyleMap(_defaultSubPresets[name]!);
                });
              })),
              ..._userPresets.keys.map((name) => GestureDetector(
                onLongPress: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      title: const Text('Delete Preset?', style: TextStyle(color: Colors.white)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _deleteUserPreset(name);
                  }
                },
                child: _subPresetChip(name, () {
                  setState(() {
                    _applyStyleMap(_userPresets[name]!);
                  });
                }),
              )),
            ],
          ),
        ),
        const Divider(height: 32, color: Colors.white10),
        const Text('Layout & Behavior', style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Alignment', style: TextStyle(fontSize: 12, color: Colors.white70)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icons.align_horizontal_left, Icons.align_horizontal_center, Icons.align_horizontal_right].asMap().entries.map((e) {
                final isSelected = _subAlign == e.key;
                return IconButton(
                  icon: Icon(e.value, color: isSelected ? Colors.redAccent : Colors.white38, size: 20),
                  onPressed: () {
                    setState(() {
                      _subAlign = e.key;
                      _notifyChanges();
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
        _buildSlider('Bottom Offset', _subPositionOffset, 0, 200, (v) {
          setState(() {
            _subPositionOffset = v;
            _notifyChanges();
          });
        }),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Override Embedded Styles', style: TextStyle(fontSize: 12, color: Colors.white70)),
          subtitle: const Text('Force these styles on MKV/ASS subtitles', style: TextStyle(fontSize: 10, color: Colors.white38)),
          value: _overrideAss,
          activeThumbColor: Colors.redAccent,
          onChanged: (v) {
            setState(() {
              _overrideAss = v;
              _notifyChanges();
            });
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _subPresetChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 35, child: Text(value.toStringAsFixed(min < 1 && max <= 3 ? 2 : 1), style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _tabToggleButton(String label, bool active, ValueChanged<bool> onChanged) {
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(!active),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.redAccent.withValues(alpha: 0.15) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? Colors.redAccent : Colors.white10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: active ? Colors.redAccent : Colors.white54)),
        ),
      ),
    );
  }
}
