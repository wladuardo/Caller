import SwiftUI
import WebRTC

struct WebRTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack
    var mirror = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        track.add(view)
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
        uiView.renderFrame(nil)
    }
}
