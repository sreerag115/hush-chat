import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../services/webrtc_service.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final webrtc = Provider.of<WebRtcService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          // ── Video streams ────────────────────────────────────────────────
          if (webrtc.callState == CallState.connected && webrtc.isVideoCall) ...[
            Positioned.fill(
              child: RTCVideoView(
                webrtc.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
            if (!webrtc.isCameraOff)
              Positioned(
                top: 56,
                right: 16,
                width: 110,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(
                    webrtc.localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: true,
                  ),
                ),
              ),
          ],

          // ── Caller profile (voice / connecting / ringing) ────────────────
          if (!(webrtc.callState == CallState.connected && webrtc.isVideoCall))
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pulsingAvatar(webrtc, theme),
                  const SizedBox(height: 28),
                  Text(
                    webrtc.targetPhone ?? webrtc.targetUid ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _stateLabel(webrtc),
                    style: TextStyle(
                      fontSize: 14,
                      color: webrtc.callState == CallState.connected
                          ? theme.colorScheme.secondary
                          : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),

          // ── Encryption badge ─────────────────────────────────────────────
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 12, color: theme.colorScheme.secondary),
                    const SizedBox(width: 6),
                    const Text('E2EE · Firebase Signaling · WebRTC P2P',
                        style: TextStyle(fontSize: 10, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),

          // ── Action buttons ───────────────────────────────────────────────
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: _buildActions(webrtc, theme),
          ),
        ],
      ),
    );
  }

  Widget _pulsingAvatar(WebRtcService webrtc, ThemeData theme) {
    final label = webrtc.targetPhone ?? webrtc.targetUid ?? '?';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withOpacity(0.06),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: CircleAvatar(
        radius: 60,
        backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
        child: Text(
          label.length >= 2 ? label.substring(label.length - 2) : '?',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  String _stateLabel(WebRtcService webrtc) {
    switch (webrtc.callState) {
      case CallState.ringing:
        return webrtc.isIncoming ? 'Incoming Secure Call...' : 'Ringing...';
      case CallState.connecting:
        return 'Connecting E2EE P2P Session...';
      case CallState.connected:
        return 'Secure Call Active';
      default:
        return '';
    }
  }

  Widget _buildActions(WebRtcService webrtc, ThemeData theme) {
    // Incoming ringing — show Accept / Decline side by side
    if (webrtc.callState == CallState.ringing && webrtc.isIncoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(
            icon: Icons.call_end,
            color: Colors.red,
            onTap: webrtc.hangUp,
            size: 64,
          ),
          _circleBtn(
            icon: Icons.call,
            color: Colors.teal,
            onTap: webrtc.acceptCall,
            size: 64,
          ),
        ],
      );
    }

    // Connecting / active — control bar
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _iconToggleBtn(
            icon: webrtc.isMuted ? Icons.mic_off : Icons.mic,
            label: webrtc.isMuted ? 'Unmute' : 'Mute',
            active: webrtc.isMuted,
            onTap: webrtc.toggleMute,
          ),
          _iconToggleBtn(
            icon: webrtc.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            label: 'Speaker',
            active: webrtc.isSpeakerOn,
            color: theme.colorScheme.secondary,
            onTap: webrtc.toggleSpeaker,
          ),
          if (webrtc.isVideoCall)
            _iconToggleBtn(
              icon: webrtc.isCameraOff ? Icons.videocam_off : Icons.videocam,
              label: 'Camera',
              active: webrtc.isCameraOff,
              onTap: webrtc.toggleCamera,
            ),
          _circleBtn(icon: Icons.call_end, color: Colors.red, onTap: webrtc.hangUp, size: 52),
        ],
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 52,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }

  Widget _iconToggleBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? Colors.redAccent : (color ?? Colors.white), size: 26),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}
