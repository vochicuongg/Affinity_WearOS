// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — audio_service.dart
//
//  Two responsibilities:
//   1. RECORDING: `record` package → AAC-LC / m4a for small file size.
//      Polls amplitude every 50 ms and broadcasts to a stream for waveform.
//   2. PLAYBACK: `just_audio` package → plays decrypted temp file at
//      "Whisper Level" (35% volume) for privacy when held to the ear.
//
//  AudioSession is configured once at startup with spokenAudio mode,
//  which tells Android to route audio via the earpiece on Wear OS and
//  request exclusive audio focus (no music/podcast overlap).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../utils/logger.dart';

// ── Whisper volume constant ───────────────────────────────────────────────────

/// 35% volume: audible when held to the ear, inaudible from 30 cm away.
const double kWhisperVolume = 0.35;

/// Maximum recording duration before auto-stop (prevents runaway recordings).
const Duration kMaxRecordDuration = Duration(seconds: 30);

// ── AudioService ──────────────────────────────────────────────────────────────

class AudioService {
  static const _tag = 'AudioService';

  final AudioRecorder _recorder = AudioRecorder();
  AudioPlayer? _player;

  // Amplitude stream for the waveform painter
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Timer? _amplitudeTimer;
  Timer? _maxDurationTimer;
  bool _isRecording = false;

  // ── Session configuration ─────────────────────────────────────────────────

  /// Call once in main() or on first use.
  /// Configures Android audio to use spokenAudio mode via the earpiece.
  static Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientExclusive,
        androidWillPauseWhenDucked: true,
      ),
    );
    Log.i(_tag, 'AudioSession configured (spokenAudio mode)');
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to [outputPath] (should end in `.m4a`).
  ///
  /// Config: AAC-LC, 64 kbps, 16 kHz, mono — good quality at ~480 KB/min.
  /// Automatically stops after [kMaxRecordDuration].
  Future<void> startRecording(String outputPath) async {
    if (_isRecording) {
      Log.w(_tag, 'startRecording called while already recording — ignored');
      return;
    }

    if (!await hasPermission()) {
      Log.e(_tag, 'Microphone permission not granted');
      throw Exception('Microphone permission required');
    }

    await _recorder.start(
      const RecordConfig(
        encoder:    AudioEncoder.aacLc,
        bitRate:    64000,   // 64 kbps — compact for watch storage
        sampleRate: 16000,   // 16 kHz — sufficient for voice
        numChannels: 1,       // mono
      ),
      path: outputPath,
    );

    _isRecording = true;
    Log.i(_tag, 'Recording started → $outputPath');

    // Poll amplitude for waveform (50 ms interval)
    _amplitudeTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) async {
        if (!_isRecording) return;
        final amp = await _recorder.getAmplitude();
        // Normalise dBFS (typically -160..0) to 0..1
        final normalised = ((amp.current + 40) / 40).clamp(0.0, 1.0);
        _amplitudeController.add(normalised);
      },
    );

    // Auto-stop after max duration
    _maxDurationTimer = Timer(kMaxRecordDuration, () async {
      if (_isRecording) {
        Log.w(_tag, 'Max recording duration reached — auto-stopping');
        await stopRecording();
      }
    });
  }

  /// Stops recording and returns the path of the recorded file.
  /// Returns `null` if not currently recording.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _isRecording = false;
    _amplitudeController.add(0.0); // reset waveform

    final path = await _recorder.stop();
    Log.i(_tag, 'Recording stopped → $path');

    if (path == null) return null;

    final file = File(path);
    final sizeKb = file.lengthSync() ~/ 1024;
    Log.i(_tag, 'Recorded file: ${sizeKb}KB');
    return path;
  }

  bool get isRecording => _isRecording;

  // ── Playback ──────────────────────────────────────────────────────────────

  /// Plays the audio file at [filePath] at whisper volume (35%).
  /// [onComplete] is called when playback finishes — use for secure wipe.
  Future<void> playWhisper(
    String filePath, {
    VoidCallback? onComplete,
    double volume = kWhisperVolume,
  }) async {
    final session = await AudioSession.instance;
    final acquired = await session.setActive(true);
    if (!acquired) {
      Log.w(_tag, 'Could not acquire audio focus');
    }

    _player?.dispose();
    _player = AudioPlayer();

    await _player!.setVolume(volume);
    await _player!.setFilePath(filePath);

    _player!.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed) {
        Log.i(_tag, 'Whisper playback complete');
        session.setActive(false);
        onComplete?.call();
      }
    });

    await _player!.play();
    Log.i(_tag, 'Playing whisper at ${(volume * 100).round()}% volume');
  }

  Future<void> stopPlayback() async {
    await _player?.stop();
    await _player?.dispose();
    _player = null;
  }

  bool get isPlaying => _player?.playing ?? false;

  // ── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _amplitudeTimer?.cancel();
    _maxDurationTimer?.cancel();
    await _recorder.dispose();
    await _player?.dispose();
    await _amplitudeController.close();
  }
}

// Typedef used by playWhisper callback
typedef VoidCallback = void Function();
