import 'package:audioplayers/audioplayers.dart';
import 'package:logger/logger.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final Logger _logger = Logger();
  AudioPlayer? _waterFlowPlayer;
  AudioPlayer? _waterStopPlayer;
  bool _isInitialized = false;
  bool _soundsEnabled = true;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _waterFlowPlayer = AudioPlayer();
      _waterStopPlayer = AudioPlayer();

      // Set up water flow sound (looping)
      await _waterFlowPlayer!.setReleaseMode(ReleaseMode.loop);
      await _waterFlowPlayer!.setVolume(0.3); // Lower volume for ambient sound

      // Set up water stop sound (one-time)
      await _waterStopPlayer!.setReleaseMode(ReleaseMode.release);
      await _waterStopPlayer!.setVolume(0.5);

      _isInitialized = true;
      _logger.i('Sound service initialized');
    } catch (e) {
      _logger.e('Failed to initialize sound service: $e');
    }
  }

  Future<void> playWaterFlowStart() async {
    if (!_soundsEnabled) return;
    if (!_isInitialized) await initialize();

    try {
      if (_waterFlowPlayer != null) {
        // Try to play custom water flow sound, fallback to system sound if not available
        try {
          await _waterFlowPlayer!.play(AssetSource('sounds/water_flow.mp3'));
          _logger.i('Playing water flow start sound');
        } catch (e) {
          _logger.w('Custom water flow sound not found, using system sound');
          await _playSystemWaterSound();
        }
      }
    } catch (e) {
      _logger.e('Failed to play water flow sound: $e');
    }
  }

  Future<void> playWaterFlowStop() async {
    if (!_soundsEnabled) return;
    if (!_isInitialized) await initialize();

    try {
      // Stop the flowing sound
      if (_waterFlowPlayer != null) {
        await _waterFlowPlayer!.stop();
      }

      // Play stop sound
      if (_waterStopPlayer != null) {
        try {
          await _waterStopPlayer!.play(AssetSource('sounds/water_stop.mp3'));
          _logger.i('Playing water flow stop sound');
        } catch (e) {
          _logger.w('Custom water stop sound not found, using system sound');
          await _playSystemWaterSound();
        }
      }
    } catch (e) {
      _logger.e('Failed to play water stop sound: $e');
    }
  }

  Future<void> stopWaterFlow() async {
    try {
      if (_waterFlowPlayer != null) {
        await _waterFlowPlayer!.stop();
        _logger.i('Stopped water flow sound');
      }
    } catch (e) {
      _logger.e('Failed to stop water flow sound: $e');
    }
  }

  Future<void> _playSystemWaterSound() async {
    try {
      if (_waterStopPlayer != null) {
        // Use a simple notification sound as fallback
        await _waterStopPlayer!.play(AssetSource('sounds/notification.mp3'));
        _logger.i('Playing system water sound');
      }
    } catch (e) {
      _logger.w('System sound not available, skipping audio feedback');
    }
  }

  Future<void> playNotificationSound() async {
    if (!_soundsEnabled) return;
    if (!_isInitialized) await initialize();

    try {
      if (_waterStopPlayer != null) {
        // Play a short notification sound for button presses
        try {
          await _waterStopPlayer!.play(AssetSource('sounds/notification.mp3'));
          _logger.i('Playing notification sound');
        } catch (e) {
          _logger.w('Custom notification sound not found, using system sound');
          await _playSystemNotificationSound();
        }
      }
    } catch (e) {
      _logger.e('Failed to play notification sound: $e');
    }
  }

  Future<void> _playSystemNotificationSound() async {
    try {
      if (_waterStopPlayer != null) {
        // Use a simple system notification sound as fallback
        await _waterStopPlayer!.play(AssetSource('sounds/notification.mp3'));
        _logger.i('Playing system notification sound');
      }
    } catch (e) {
      _logger.w(
          'System notification sound not available, skipping audio feedback');
    }
  }

  void setSoundsEnabled(bool enabled) {
    _soundsEnabled = enabled;
    _logger.i('Sounds ${enabled ? 'enabled' : 'disabled'}');
  }

  bool get soundsEnabled => _soundsEnabled;

  Future<void> dispose() async {
    try {
      await _waterFlowPlayer?.dispose();
      await _waterStopPlayer?.dispose();
      _waterFlowPlayer = null;
      _waterStopPlayer = null;
      _isInitialized = false;
      _logger.i('Sound service disposed');
    } catch (e) {
      _logger.e('Failed to dispose sound service: $e');
    }
  }
}
