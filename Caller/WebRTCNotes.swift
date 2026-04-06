import Foundation

/*
 Current WebRTC integration:

 - WebRTCCallService now owns RTCPeerConnectionFactory, RTCPeerConnection,
   local audio/video tracks, ICE handling, and camera capture.
 - SwiftUI renders RTCVideoTrack objects through a UIViewRepresentable wrapper
   around RTCMTLVideoView.
 - SignalingPayload carries offer, answer, and structured ICE candidate data.
 - AppEnvironment still defaults to a mock signaling implementation; for real
   device-to-device calls, swap in WebSocketSignalingService backed by your
   signaling server and route messages by user/call ID.

 Signaling server contract:

 - The iOS client opens a WebSocket connection to the URL stored in the
   SignalingServerURL Info.plist key.
 - Each WebSocket message is a JSON-encoded SignalingMessage.
 - Your server should deliver each message to the connected client identified
   by toUserID and preserve callID.
 - Expected payloads:
   offer(sdp: String)
   answer(sdp: String)
   iceCandidate({ sdp: String, sdpMLineIndex: Int32, sdpMid: String? })
   hangup
 */
