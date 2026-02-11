import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'data_validator.dart';

/// A region entry with its associated plants.
class RegionEntry {
  final String country;
  final String? region;
  final List<RegionPlant> plants;

  RegionEntry({
    required this.country,
    this.region,
    required this.plants,
  });

  /// Display name like "California, USA" or "Kenya".
  String get displayName {
    if (region != null) return '$region, $country';
    return country;
  }
}

/// A plant entry parsed from the region file format "Genus species (Common Name)".
class RegionPlant {
  final String scientificName;
  final String commonName;
  final String raw;

  RegionPlant({
    required this.scientificName,
    required this.commonName,
    required this.raw,
  });
}

/// Service for looking up which plants are available in a given region.
/// Loads from Locally_Growing_Plants_by_Region.json.
class RegionPlantService {
  final List<RegionEntry> _entries = [];

  /// Index: lowercase search term -> list of matching RegionEntry references.
  /// Contains entries for country names, region names, and combined forms.
  final Map<String, List<RegionEntry>> _index = {};

  bool _isInitialized = false;

  static const String _assetPath =
      'assets/plant_data/Locally_Growing_Plants_by_Region.json';

  bool get isInitialized => _isInitialized;
  int get regionCount => _entries.length;

  /// Load and index region data from bundled JSON asset.
  Future<void> initialize({
    void Function(double progress, String status)? onProgress,
  }) async {
    if (_isInitialized) return;

    onProgress?.call(0.0, 'Loading region plant database...');

    final jsonString = await rootBundle.loadString(_assetPath);
    final List<dynamic> rawEntries = jsonDecode(jsonString);

    onProgress?.call(0.3, 'Validating ${rawEntries.length} region entries...');
    DataValidator.validateRegionEntries(rawEntries);

    onProgress?.call(0.5, 'Indexing regions...');

    for (final raw in rawEntries) {
      final map = raw as Map<String, dynamic>;
      final country = map['Country'] as String;
      final region = map['Region'] as String?;
      final plantStrings = (map['Plants'] as List).cast<String>();

      final plants = plantStrings.map(_parsePlantString).toList();
      final entry = RegionEntry(
        country: country,
        region: region,
        plants: plants,
      );
      _entries.add(entry);

      // Index by country name
      _addToIndex(country.toLowerCase(), entry);

      // Index by region name if present
      if (region != null) {
        _addToIndex(region.toLowerCase(), entry);
        // Also index combined form: "region, country"
        _addToIndex('${region.toLowerCase()}, ${country.toLowerCase()}', entry);
      }
    }

    _isInitialized = true;
    onProgress?.call(1.0, 'Region database ready (${_entries.length} regions)');
  }

  /// Find regions matching a location query.
  /// Tries exact match first, then substring matching.
  /// Returns all matching RegionEntry objects.
  List<RegionEntry> findRegions(String query) {
    if (!_isInitialized) return [];

    final q = query.trim().toLowerCase();

    // 1. Exact match on any indexed key
    final exact = _index[q];
    if (exact != null && exact.isNotEmpty) return exact;

    // 2. Substring match: query contains index key or vice versa
    final matches = <RegionEntry>{};
    for (final indexEntry in _index.entries) {
      if (indexEntry.key.contains(q) || q.contains(indexEntry.key)) {
        matches.addAll(indexEntry.value);
      }
    }

    return matches.toList();
  }

  /// Get all unique country names in the database.
  List<String> get countries {
    return _entries.map((e) => e.country).toSet().toList()..sort();
  }

  /// Parse "Genus species (Common Name)" into a RegionPlant.
  /// Falls back gracefully if no parenthetical common name is present.
  static RegionPlant _parsePlantString(String raw) {
    final parenMatch = RegExp(r'^(.+?)\s*\(([^)]+)\)$').firstMatch(raw);
    if (parenMatch != null) {
      return RegionPlant(
        scientificName: parenMatch.group(1)!.trim(),
        commonName: parenMatch.group(2)!.trim(),
        raw: raw,
      );
    }
    // No parenthetical — use the whole string as both
    return RegionPlant(
      scientificName: raw.trim(),
      commonName: raw.trim(),
      raw: raw,
    );
  }

  void _addToIndex(String key, RegionEntry entry) {
    _index.putIfAbsent(key, () => []).add(entry);
  }
}