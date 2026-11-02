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
    this.title = 'Choose Project Location',
    this.confirmLabel = 'Confirm Location',
    this.consumeSharedLocation = true,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String title;
  final String confirmLabel;
  final bool consumeSharedLocation;

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
  CurrentDeviceLocation? _selectedLocation;
  List<LocationSearchResult> _searchResults = [];
  String? _searchError;
  bool _searching = false;
  bool _resolvingAddress = false;
  bool _lookingUpAddress = false;
  bool _locating = false;
  bool _settingSearchText = false;
  String? _addressLookupError;
  bool _hasHandledSharedLocation = false;
  Timer? _searchDebounce;
  Timer? _addressDebounce;
  int _searchGeneration = 0;
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
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = _initialCenter;
      _scheduleAddressLookup(_initialCenter);
    }
    if (widget.consumeSharedLocation) {
      _sharedTextSubscription =
          SharedLocationService.instance.sharedTexts.listen(
        (_) => unawaited(_consumeInitialSharedText()),
      );
      unawaited(_consumeInitialSharedText());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_useCurrentLocation(initial: true));
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _addressDebounce?.cancel();
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
      _hasHandledSharedLocation = true;
      _selectPoint(point);
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
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 3) return;
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final results = await LocationSearchService.instance.search(query);
      if (!mounted ||
          generation != _searchGeneration ||
          _searchController.text.trim() != query) {
        return;
      }
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _searchError = 'No matching places found. Try a nearby city or area.';
        }
      });
    } on LocationSearchException catch (error) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searchError = error.message);
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    if (_settingSearchText) return;
    _searchDebounce?.cancel();
    _searchGeneration++;
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _searching = false;
        _searchResults = [];
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 550),
      _searchLocations,
    );
  }

  void _selectSearchResult(LocationSearchResult result) {
    FocusScope.of(context).unfocus();
    final point = LatLng(result.latitude, result.longitude);
    _settingSearchText = true;
    _searchController.text = result.name;
    _settingSearchText = false;
    final location = CurrentDeviceLocation(
      address: result.name,
      latitude: result.latitude,
      longitude: result.longitude,
      placeName: result.placeName,
      street: result.street,
      locality: result.locality,
      city: result.city,
      state: result.state,
      postalCode: result.postalCode,
      country: result.country,
    );
    _selectPoint(point, location: location, zoom: 16);
  }

  void _selectPoint(
    LatLng point, {
    CurrentDeviceLocation? location,
    double? zoom,
  }) {
    setState(() {
      _selectedPoint = point;
      _selectedLocation = location;
      _lookingUpAddress = false;
      _addressLookupError = null;
      _searchResults = [];
      _searchError = null;
      _searching = false;
    });
    _addressDebounce?.cancel();
    if (location == null) _scheduleAddressLookup(point);
    if (zoom != null) _mapController.move(point, zoom);
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    final point = camera.center;
    if (_selectedPoint == point) return;
    _selectPoint(point);
  }

  void _scheduleAddressLookup(LatLng point) {
    _addressDebounce?.cancel();
    _addressDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _lookupAddress(point),
    );
  }

  Future<void> _lookupAddress(LatLng point) async {
    setState(() => _lookingUpAddress = true);
    try {
      final location =
          await CurrentLocationService.instance.getLocationForCoordinates(
        point.latitude,
        point.longitude,
      );
      if (!mounted || _selectedPoint != point) return;
      setState(() {
        _selectedLocation = location;
        _addressLookupError = null;
      });
    } on CurrentLocationException catch (error) {
      if (mounted && _selectedPoint == point) {
        setState(() {
          _selectedLocation = null;
          _addressLookupError = error.message;
        });
      }
    } finally {
      if (mounted && _selectedPoint == point) {
        setState(() => _lookingUpAddress = false);
      }
    }
  }

  Future<void> _useCurrentLocation({bool initial = false}) async {
    if (_locating || (initial && _hasHandledSharedLocation)) return;
    setState(() => _locating = true);
    try {
      final location =
          await CurrentLocationService.instance.getCurrentLocation();
      if (!mounted || (initial && _hasHandledSharedLocation)) return;
      _selectPoint(
        LatLng(location.latitude, location.longitude),
        location: _locationHasAddress(location) ? location : null,
        zoom: 16,
      );
    } on CurrentLocationException catch (error) {
      if (initial) {
        _showMessage('Could not find your current location. $error');
      } else {
        _showMessage(error.message);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _confirmLocation() async {
    final point = _selectedPoint;
    if (point == null || _resolvingAddress) return;

    setState(() => _resolvingAddress = true);
    try {
      final location = _selectedLocation ?? await _locationOrCoordinates(point);
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

  bool _locationHasAddress(CurrentDeviceLocation location) =>
      !location.address.startsWith('Coordinates:');

  Future<CurrentDeviceLocation> _locationOrCoordinates(LatLng point) async {
    try {
      return await CurrentLocationService.instance.getLocationForCoordinates(
        point.latitude,
        point.longitude,
      );
    } on CurrentLocationException {
      return CurrentDeviceLocation(
        address: 'Coordinates: ${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}',
        latitude: point.latitude,
        longitude: point.longitude,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          widget.title,
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
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) => _searchLocations(),
                        decoration: InputDecoration(
                          hintText: 'Search address, place, landmark, or area',
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
                onPositionChanged: _onMapPositionChanged,
                onTap: (_, point) => _selectPoint(
                  point,
                  zoom: _mapController.camera.zoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.buid_arch',
                ),
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 42),
                      child: Icon(
                        Icons.location_pin,
                        size: 48,
                        color: AppColors.error,
                        shadows: [
                          Shadow(color: Colors.white, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: FloatingActionButton(
                    heroTag: 'location-picker-current-location',
                    tooltip: 'Use current location',
                    onPressed: _locating ? null : _useCurrentLocation,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.secondary,
                    child: _locating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
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
                  if (_selectedPoint == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Move the map to place the pin, or search for a place.',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    _selectedAddressPanel(),
                  Opacity(
                    opacity: _selectedPoint == null ? 0.4 : 1,
                    child: IgnorePointer(
                      ignoring: _selectedPoint == null || _resolvingAddress,
                      child: AuthButton(
                        label: _resolvingAddress
                            ? 'Confirming location...'
                            : widget.confirmLabel,
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

  Widget _selectedAddressPanel() {
    final location = _selectedLocation;
    final title = location?.placeName ??
        location?.street ??
        location?.city ??
        (location?.address.startsWith('Coordinates:') == true
            ? 'Selected location'
            : location?.address);
    final details = <(String, String?)>[
      ('Street', location?.street),
      ('Locality', location?.locality),
      ('City', location?.city),
      ('State', location?.state),
      ('Postal code', location?.postalCode),
      ('Country', location?.country),
    ].where((item) => item.$2?.trim().isNotEmpty == true).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: AppColors.secondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _lookingUpAddress
                      ? 'Finding address...'
                      : title ?? 'Selected location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (_lookingUpAddress)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (location != null &&
              location.address != title &&
              !location.address.startsWith('Coordinates:')) ...[
            const SizedBox(height: 4),
            Text(
              location.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
          if (_addressLookupError != null) ...[
            const SizedBox(height: 4),
            Text(
              'Address details unavailable. You can still confirm this pin.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, value) in details)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$label: $value'),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
