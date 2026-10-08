import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages app-wide user presence, keeping Realtime presence status in sync
/// and periodically updating the user's `last_seen_at` timestamp.
///
/// Each online user tracks their presence on their personal channel
/// `presence:user:<userId>`. Peers viewing direct message chats or profiles
/// subscribe to that channel to know instantly if the user is currently
/// in-app, or fall back to formatting the user's `last_seen_at` timestamp.
class PresenceService with WidgetsBindingObserver {
  PresenceService._internal();

  static final PresenceService instance = PresenceService._internal();

  factory PresenceService() => instance;

  String? _currentUserId;
  RealtimeChannel? _myPresenceChannel;
  Timer? _heartbeatTimer;
  bool _observerRegistered = false;
  bool _isTracking = false;

  /// Starts tracking presence and updating last seen for the signed-in user.
  void start(String userId) {
    if (_currentUserId == userId && _myPresenceChannel != null) {
      return;
    }
    stop();

    _currentUserId = userId;
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    _subscribeAndTrack();
    _startHeartbeat();
  }

  void _subscribeAndTrack() {
    final uid = _currentUserId;
    if (uid == null) return;

    final client = Supabase.instance.client;
    final channel = client.channel('presence:user:$uid');
    _myPresenceChannel = channel;

    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _isTracking = true;
        await _trackSelf();
        _updateLastSeen();
      }
    });
  }

  Future<void> _trackSelf() async {
    final channel = _myPresenceChannel;
    final uid = _currentUserId;
    if (channel == null || uid == null) return;
    try {
      await channel.track({
        'user_id': uid,
        'online': true,
      });
    } catch (_) {}
  }

  Future<void> _untrackSelf() async {
    final channel = _myPresenceChannel;
    if (channel == null) return;
    try {
      await channel.untrack();
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Heartbeat every 60 seconds while the app remains active in foreground.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _updateLastSeen();
    });
  }

  Future<void> _updateLastSeen() async {
    if (_currentUserId == null) return;
    try {
      await Supabase.instance.client.rpc('update_last_seen');
    } catch (_) {}
  }

  /// Stops presence tracking and cleans up channels/heartbeats.
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final channel = _myPresenceChannel;
    _myPresenceChannel = null;
    _isTracking = false;
    _currentUserId = null;

    if (channel != null) {
      try {
        await channel.untrack();
      } catch (_) {}
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_currentUserId == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _startHeartbeat();
        final channel = _myPresenceChannel;
        if (channel != null && _isTracking) {
          _trackSelf();
        } else {
          _subscribeAndTrack();
        }
        _updateLastSeen();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        _untrackSelf();
        _updateLastSeen();
        break;
    }
  }

  /// Subscribes to another user's presence channel and calls [onStatusChange]
  /// whenever their online status changes. Returns the [RealtimeChannel].
  RealtimeChannel createPeerPresenceSubscription({
    required String peerId,
    required void Function(bool isOnline) onStatusChange,
  }) {
    final channel = Supabase.instance.client.channel('presence:user:$peerId');

    void check() {
      final states = channel.presenceState();
      final isOnline = states.any((s) => s.presences.isNotEmpty);
      onStatusChange(isOnline);
    }

    channel
        .onPresenceSync((_) => check())
        .onPresenceJoin((_) => onStatusChange(true))
        .onPresenceLeave((_) => check())
        .subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        check();
      }
    });

    return channel;
  }

  /// Safely removes a peer presence subscription channel.
  void removeSubscription(RealtimeChannel? channel) {
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Formats a [lastSeen] timestamp into a user-friendly string:
  /// - "< 60s": `last active just now`
  /// - "< 60m": `last active 5 mins ago`
  /// - Today: `last active today at 10:28 AM`
  /// - Yesterday: `last active yesterday at 8:15 PM`
  /// - Within 7 days: `last active Monday at 10:28 AM`
  /// - Older: `last active 12 Sep`
  static String formatLastActive(DateTime lastSeen) {
    final local = lastSeen.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.isNegative || diff.inSeconds < 60) {
      return 'last active just now';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'last active $m min${m == 1 ? '' : 's'} ago';
    }

    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(date).inDays;

    final timeStr = DateFormat.jm().format(local);
    if (dayDiff == 0) {
      return 'last active today at $timeStr';
    }
    if (dayDiff == 1) {
      return 'last active yesterday at $timeStr';
    }
    if (dayDiff < 7 && dayDiff > 0) {
      final dayName = DateFormat('EEEE').format(local);
      return 'last active $dayName at $timeStr';
    }
    if (local.year != now.year) {
      return 'last active ${DateFormat('d MMM yyyy').format(local)}';
    }
    return 'last active ${DateFormat('d MMM').format(local)}';
  }
}
