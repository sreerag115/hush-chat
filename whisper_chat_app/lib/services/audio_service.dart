import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? _currentRecordPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  AudioPlayer get player => _player;

  /// Request microphone permission
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Start recording audio and save to temporary file
  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPermission = await requestMicPermission();
    if (!hasPermission) {
      throw Exception("Microphone permission denied");
    }

    final tempDir = await getTemporaryDirectory();
    final fileName = 'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final filePath = '${tempDir.path}/$fileName';
    _currentRecordPath = filePath;

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );
    _isRecording = true;
  }

  /// Stop recording audio and return the local file
  Future<File?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;

    if (path != null) {
      return File(path);
    }
    return null;
  }

  /// Play a local or remote audio file
  Future<void> playAudio(String sourcePath, {bool isRemote = false}) async {
    await _player.stop();
    if (isRemote) {
      await _player.play(UrlSource(sourcePath));
    } else {
      await _player.play(DeviceFileSource(sourcePath));
    }
  }

  /// Pause audio playback
  Future<void> pauseAudio() async {
    await _player.pause();
  }

  /// Resume audio playback
  Future<void> resumeAudio() async {
    await _player.resume();
  }

  /// Stop audio playback
  Future<void> stopAudio() async {
    await _player.stop();
  }

  /// Dispose resources
  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
