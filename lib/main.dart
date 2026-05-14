import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double _metersPerMile = 1609.344;
const String _tripHistoryKey = 'trip_history';

void main() {
  runApp(const MileageTrackerApp());
}

class MileageTrackerApp extends StatelessWidget {
  const MileageTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D6E6E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mileage Tracker',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF3F6F8),
        useMaterial3: true,
      ),
      home: const MileageDashboard(),
    );
  }
}

class TripRecord {
  const TripRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.miles,
    required this.durationSeconds,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final double miles;
  final int durationSeconds;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'miles': miles,
      'durationSeconds': durationSeconds,
    };
  }

  factory TripRecord.fromJson(Map<String, dynamic> json) {
    return TripRecord(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: DateTime.parse(json['endedAt'] as String),
      miles: (json['miles'] as num).toDouble(),
      durationSeconds: json['durationSeconds'] as int,
    );
  }
}

class MileageDashboard extends StatefulWidget {
  const MileageDashboard({super.key});

  @override
  State<MileageDashboard> createState() => _MileageDashboardState();
}

class _MileageDashboardState extends State<MileageDashboard> {
  final List<TripRecord> _history = <TripRecord>[];

  SharedPreferences? _preferences;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  DateTime? _sessionStartedAt;

  bool _isLoading = true;
  bool _isTracking = false;
  bool _isBusy = false;
  double _sessionMiles = 0;
  double _currentSpeedMph = 0;
  String _statusText = 'Ready to track your next drive.';

  @override
  void initState() {
    super.initState();
    _loadTripHistory();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTripHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final rawHistory = preferences.getString(_tripHistoryKey);
    final List<TripRecord> decodedHistory;

    if (rawHistory == null || rawHistory.isEmpty) {
      decodedHistory = <TripRecord>[];
    } else {
      final decodedList = jsonDecode(rawHistory) as List<dynamic>;
      decodedHistory = decodedList
          .map(
            (dynamic item) => TripRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _preferences = preferences;
      _history
        ..clear()
        ..addAll(decodedHistory);
      _isLoading = false;
    });
  }

  Future<void> _saveTripHistory() async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    _preferences = preferences;

    final encodedHistory = jsonEncode(
      _history.map((TripRecord trip) => trip.toJson()).toList(),
    );

    await preferences.setString(_tripHistoryKey, encodedHistory);
  }

  Future<void> _toggleTracking() async {
    if (_isBusy) {
      return;
    }

    if (_isTracking) {
      await _stopTracking();
      return;
    }

    await _startTracking();
  }

  Future<void> _startTracking() async {
    setState(() {
      _isBusy = true;
      _statusText = 'Checking location access...';
    });

    final permissionError = await _ensureLocationReady();
    if (permissionError != null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusText = permissionError;
      });
      return;
    }

    Position? initialPosition;
    try {
      initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
    } catch (_) {
      initialPosition = null;
    }

    await _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 10,
          ),
        ).listen(
          _handlePositionUpdate,
          onError: (Object error) {
            if (!mounted) {
              return;
            }

            setState(() {
              _statusText = 'Location updates failed: $error';
            });
          },
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = false;
      _isTracking = true;
      _sessionMiles = 0;
      _currentSpeedMph = 0;
      _lastPosition = initialPosition;
      _sessionStartedAt = DateTime.now();
      _statusText = initialPosition == null
          ? 'Drive started. Waiting for a GPS fix.'
          : 'Drive started. Mileage is being tracked.';
    });
  }

  Future<void> _stopTracking() async {
    setState(() {
      _isBusy = true;
      _statusText = 'Saving trip...';
    });

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final endedAt = DateTime.now();
    final startedAt = _sessionStartedAt ?? endedAt;
    final durationSeconds = endedAt.difference(startedAt).inSeconds;

    final trip = TripRecord(
      id: startedAt.microsecondsSinceEpoch.toString(),
      startedAt: startedAt,
      endedAt: endedAt,
      miles: _sessionMiles,
      durationSeconds: durationSeconds,
    );

    _history.insert(0, trip);
    await _saveTripHistory();

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = false;
      _isTracking = false;
      _sessionMiles = 0;
      _currentSpeedMph = 0;
      _lastPosition = null;
      _sessionStartedAt = null;
      _statusText = 'Trip saved to local history.';
    });
  }

  Future<String?> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Turn on Location Services before starting a drive.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return 'Location permission is required to measure mileage.';
    }

    if (permission == LocationPermission.deniedForever) {
      return 'Location permission is permanently denied. Update it in Settings.';
    }

    return null;
  }

  void _handlePositionUpdate(Position position) {
    if (!_isTracking || !mounted) {
      return;
    }

    var additionalMiles = 0.0;

    if (_lastPosition != null) {
      final meters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (meters >= 8 && meters <= 1000) {
        additionalMiles = meters / _metersPerMile;
      }
    }

    setState(() {
      _lastPosition = position;
      _sessionMiles += additionalMiles;
      _currentSpeedMph = math.max(0, position.speed) * 2.23693629;
      _statusText = _currentSpeedMph >= 1
          ? 'Tracking your drive.'
          : 'Tracking is on. Start moving to log mileage.';
    });
  }

  double get _totalMiles {
    final recordedMiles = _history.fold<double>(
      0,
      (double total, TripRecord trip) => total + trip.miles,
    );
    return recordedMiles + (_isTracking ? _sessionMiles : 0);
  }

  double get _todayMiles {
    final today = DateTime.now();
    final recordedMiles = _history
        .where((TripRecord trip) => _isSameDay(trip.startedAt, today))
        .fold<double>(0, (double total, TripRecord trip) => total + trip.miles);

    if (_isTracking &&
        _sessionStartedAt != null &&
        _isSameDay(_sessionStartedAt!, today)) {
      return recordedMiles + _sessionMiles;
    }

    return recordedMiles;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final activeDuration = _sessionStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_sessionStartedAt!);

    return Scaffold(
      appBar: AppBar(title: const Text('Mileage Tracker')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Track miles while you drive',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'This version tracks distance while the app stays open in the foreground.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF51616F)),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  label: 'Today',
                  value: '${_formatMiles(_todayMiles)} mi',
                  icon: Icons.today_outlined,
                ),
                _MetricCard(
                  label: 'All trips',
                  value: _history.length.toString(),
                  icon: Icons.route_outlined,
                ),
                _MetricCard(
                  label: 'Total miles',
                  value: '${_formatMiles(_totalMiles)} mi',
                  icon: Icons.speed_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _isTracking
                                ? Icons.navigation
                                : Icons.play_circle_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isTracking
                                    ? 'Drive in progress'
                                    : 'Ready for your next drive',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusText,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _ActiveValue(
                            label: 'Miles',
                            value: _formatMiles(_sessionMiles),
                          ),
                        ),
                        Expanded(
                          child: _ActiveValue(
                            label: 'Speed',
                            value: '${_currentSpeedMph.toStringAsFixed(0)} mph',
                          ),
                        ),
                        Expanded(
                          child: _ActiveValue(
                            label: 'Duration',
                            value: _formatDuration(activeDuration),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isBusy ? null : _toggleTracking,
                        icon: Icon(
                          _isTracking
                              ? Icons.stop_circle_outlined
                              : Icons.play_arrow,
                        ),
                        label: Text(_isTracking ? 'Stop drive' : 'Start drive'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking
                              ? const Color(0xFFB3261E)
                              : Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Recent trips',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_history.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No saved trips yet. Start a drive to record your first mileage session.',
                  ),
                ),
              )
            else
              ..._history.map(
                (TripRecord trip) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TripCard(trip: trip),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static String _formatMiles(double miles) {
    return miles.toStringAsFixed(2);
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveValue extends StatelessWidget {
  const _ActiveValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(label),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final TripRecord trip;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.directions_car_outlined,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trip.miles.toStringAsFixed(2)} miles',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_formatTripDate(trip.startedAt)),
                ],
              ),
            ),
            Text(_formatTripDuration(trip.durationSeconds)),
          ],
        ),
      ),
    );
  }

  static String _formatTripDate(DateTime dateTime) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final month = months[dateTime.month - 1];
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$month ${dateTime.day}, ${dateTime.year} at $hour:$minute $meridiem';
  }

  static String _formatTripDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    return '${duration.inMinutes}m';
  }
}
