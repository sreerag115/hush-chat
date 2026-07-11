import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'firebase_service.dart';

enum CallState { idle, ringing, connecting, connected }

class WebRtcService extends ChangeNotifier {
  static final WebRtcService _instance = WebRtcService._internal();
  factory WebRtcService() => _instance;
  WebRtcService._internal();

  final FirebaseService _firebase = FirebaseService();

  CallState _callState = CallState.idle;
  String? _targetUid;
  String? _targetPhone;
  bool _isVideoCall = false;
  bool _isIncoming = false;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;

  // Getters
  CallState get callState => _callState;
  String? get targetUid => _targetUid;
  String? get targetPhone => _targetPhone;
  bool get isVideoCall => _isVideoCall;
  bool get isIncoming => _isIncoming;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;

  StreamSubscription? _signalingSubscription;
  dynamic _pendingOffer;

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _startSignalingListener();
  }

  void _startSignalingListener() {
    _signalingSubscription?.cancel();
    _signalingSubscription = _firebase.listenForSignals((signal) {
      _handleSignal(signal);
    });
  }

  void _handleSignal(Map<String, dynamic> signal) async {
    final type = signal['type'] as String;
    final from = signal['from'] as String;

    switch (type) {
      case 'call-invite':
        if (_callState != CallState.idle) {
          // Busy — send decline
          await _firebase.sendSignal(from, {
            'type': 'call-hangup',
            'reason': 'busy',
          });
          return;
        }
        _isIncoming = true;
        _targetUid = from;
        _targetPhone = signal['fromPhone'] as String?;
        _isVideoCall = signal['callType'] == 'video';
        _pendingOffer = signal['offer'];
        _callState = CallState.ringing;
        notifyListeners();
        break;

      case 'call-accept':
        if (_callState == CallState.connecting) {
          final answer = signal['answer'];
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(answer['sdp'], answer['type']),
          );
          _callState = CallState.connected;
          notifyListeners();
        }
        break;

      case 'ice-candidate':
        if (_peerConnection != null) {
          final c = signal['candidate'];
          await _peerConnection?.addCandidate(
            RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
          );
        }
        break;

      case 'call-hangup':
        _closeConnection();
        _callState = CallState.idle;
        _targetUid = null;
        _targetPhone = null;
        notifyListeners();
        break;
    }
  }

  Future<void> makeCall(String targetUid, String targetPhone, bool isVideo) async {
    _callState = CallState.connecting;
    _targetUid = targetUid;
    _targetPhone = targetPhone;
    _isVideoCall = isVideo;
    _isIncoming = false;
    notifyListeners();

    try {
      await _setupMediaDevices(isVideo);
      await _createPeerConnection();

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
      });
      await _peerConnection!.setLocalDescription(offer);

      await _firebase.sendSignal(targetUid, {
        'type': 'call-invite',
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'callType': isVideo ? 'video' : 'voice',
        'fromPhone': await _firebase.currentUser?.phoneNumber,
      });
    } catch (e) {
      debugPrint('WebRtcService makeCall error: $e');
      hangUp();
    }
  }

  Future<void> acceptCall() async {
    if (_callState != CallState.ringing || _pendingOffer == null) return;
    _callState = CallState.connecting;
    notifyListeners();

    try {
      await _setupMediaDevices(_isVideoCall);
      await _createPeerConnection();

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(_pendingOffer['sdp'], _pendingOffer['type']),
      );

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _isVideoCall,
      });
      await _peerConnection!.setLocalDescription(answer);

      await _firebase.sendSignal(_targetUid!, {
        'type': 'call-accept',
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });

      _callState = CallState.connected;
      _pendingOffer = null;
      notifyListeners();
    } catch (e) {
      debugPrint('WebRtcService acceptCall error: $e');
      hangUp();
    }
  }

  void hangUp() {
    if (_targetUid != null) {
      _firebase.sendSignal(_targetUid!, {'type': 'call-hangup'});
    }
    _closeConnection();
    _callState = CallState.idle;
    _targetUid = null;
    _targetPhone = null;
    notifyListeners();
  }

  Future<void> _setupMediaDevices(bool video) async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {
        'mandatory': {'minWidth': '640', 'minHeight': '480', 'minFrameRate': '30'},
        'facingMode': 'user',
        'optional': [],
      } : false,
    });
    localRenderer.srcObject = _localStream;
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
        {'url': 'stun:stun1.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(config, {
      'mandatory': {},
      'optional': [{'DtlsSrtpKeyAgreement': true}],
    });

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        notifyListeners();
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null && _targetUid != null) {
        _firebase.sendSignal(_targetUid!, {
          'type': 'ice-candidate',
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        hangUp();
      }
    };
  }

  void _closeConnection() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _peerConnection?.close();
    _peerConnection = null;
    _isMuted = false;
    _isCameraOff = false;
    _isSpeakerOn = false;
  }

  void toggleMute() {
    if (_localStream != null) {
      _isMuted = !_isMuted;
      _localStream!.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
      notifyListeners();
    }
  }

  void toggleCamera() {
    if (_localStream != null && _isVideoCall) {
      _isCameraOff = !_isCameraOff;
      _localStream!.getVideoTracks().forEach((t) => t.enabled = !_isCameraOff);
      notifyListeners();
    }
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    notifyListeners();
  }

  @override
  void dispose() {
    _signalingSubscription?.cancel();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _closeConnection();
    super.dispose();
  }
}
