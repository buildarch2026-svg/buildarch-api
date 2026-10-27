import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/current_location_service.dart';
import '../services/location_search_service.dart';
import '../services/shared_location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/auth_button.dart';

class ProjectLocationPickerScreen extends StatefulWidget {
  const ProjectLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<ProjectLocationPickerScreen> createState() =>
      _ProjectLocationPickerScreenState();
}

class _ProjectLocationPickerScreenState
    extends State<ProjectLocationPickerScreen> {
  static const _defaultCenter = LatLng(20.5937, 78.9629);

  late final MapController _mapController;
  final _searchController = TextEditingController();
  LatLng? _selectedPoint;
  String? _selectedAddress;
  List<LocationSearchResult> _searchResults = [];
  String? _searchError;
  bool _searching = false;
  bool _resolvingAddress = false;
  StreamSubscription<String>? _sharedTextSubscription;

  LatLng get _initialCenter {
    final latitude = widget.initialLatitude;
    final longitude = widget.initialLongitude;
    if (latitude != null && longitude != null) {
      return LatLng(latitude, longitude);
    }
    return _defaultCenter;
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _sharedTextSubscription = SharedLocationService.instance.sharedTexts.listen(
      (_) => unawaited(_consumeInitialSharedText()),
    );
    unawaited(_consumeInitialSharedText());
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _sharedTextSubscription?.cancel();
    super.dispose();
  }

  Future<void> _consumeInitialSharedText() async {
    try {
      final sharedText = await SharedLocationService.instance.takeSharedText();
      if (sharedText != null) await _handleSharedText(sharedText);
    } on SharedLocationException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _handleSharedText(String sharedText) async {
    try {
      final location = await SharedLocationService.instance.resolve(sharedText);
      if (!mounted) return;
      if (location == null) {
        _showMessage(
          'This shared item has no map coordinates. Share a Google Maps '
          'pin or location link instead.',
        );
        return;
      }

      final point = LatLng(location.latitude, location.longitude);
      setState(() {
        _selectedPoint = point;
        _selectedAddress = null;
        _searchResults = [];
        _searchError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(point, 18);
      });
      _showMessage('Shared location added. Adjust the pin before saving.');
    } on SharedLocationException catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchLocations() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = [];
    });

    try {
      final results = await LocationSearchService.instance.search(
        _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _searchError = 'No matching places found. Try a nearby city or area.';
        }
      });
    } on LocationSearchException catch (error) {
      if (mounted) setState(() => _searchError = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(LocationSearchResult result) {
    final point = LatLng(result.latitude, result.longitude);
    setState(() {
      _selectedPoint = point;
      _selectedAddress = result.name;
      _searchResults = [];
      _searchError = null;
    });
    _mapController.move(point, 16);
  }

  void _useMapCenter() {
    final point = _mapController.camera.center;
    setState(() {
      _selectedPoint = point;
      _selectedAddress = null;
      _searchResults = [];
      _searchError = null;
    });
  }

  Future<void> _confirmLocation() async {
    final point = _selectedPoint;
    if (point == null || _resolvingAddress) return;

    setState(() => _resolvingAddress = true);
    try {
      final searchedAddress = _selectedAddress;
      final location = searchedAddress == null
          ? await CurrentLocationService.instance.getLocationForCoordinates(
              point.latitude,
              point.longitude,
            )
          : CurrentDeviceLocation(
              address: searchedAddress,
              latitude: point.latitude,
              longitude: point.longitude,
            );
      if (mounted) Navigator.of(context).pop(location);
    } on CurrentLocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          'Choose Project Location',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Text(
                  'Search for the site, then zoom and move the map. Tap the '
                  'site or set the pin at the map center.',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchLocations(),
                        decoration: InputDecoration(
                          hintText: 'Search city, area, or address',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _searching ? null : _searchLocations,
                      tooltip: 'Search location',
                      icon: _searching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search),
                    ),
                  ],
                ),
                if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _searchError!,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                if (_searchResults.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.secondary,
                          ),
                          title: Text(
                            result.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: widget.initialLatitude == null ? 5 : 15,
                minZoom: 3,
                maxZoom: 19,
                onTap: (_, point) => setState(() {
                  _selectedPoint = point;
                  _selectedAddress = null;
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.buid_arch',
                ),
                if (_selectedPoint case final point?)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_pin,
                          size: 46,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  )
                else
                  const IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.add_location_alt,
                        size: 44,
                        color: AppColors.secondary,
                        shadows: [
                          Shadow(color: Colors.white, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedPoint != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _selectedAddress ??
                            'Pin selected — adjust it on the map',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _useMapCenter,
                        icon: const Icon(Icons.add_location_alt, size: 18),
                        label: const Text('Set pin here'),
                      ),
                    ],
                  ),
                  Opacity(
                    opacity: _selectedPoint == null ? 0.4 : 1,
                    child: IgnorePointer(
                      ignoring: _selectedPoint == null || _resolvingAddress,
                      child: AuthButton(
                        label: _resolvingAddress
                            ? 'Finding address...'
                            : 'Save project location',
                        onPressed: _confirmLocation,
                        backgroundColor: AppColors.primaryContainer,
                        pressedColor: AppColors.primary.withAlpha(90),
                        textStyle:
                            AppTextStyles.titleMd.copyWith(color: Colors.white),
                        leading: _resolvingAddress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.check,
                                size: 20,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
