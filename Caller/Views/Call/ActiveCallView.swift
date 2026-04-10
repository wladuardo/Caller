import SwiftUI
import WebRTC

struct ActiveCallView: View {
    let call: CallSession
    let localVideoTrack: RTCVideoTrack?
    let remoteVideoTrack: RTCVideoTrack?
    let onEnd: () -> Void
    let onToggleMute: () -> Void
    let onToggleSpeaker: () -> Void
    let onToggleCamera: () -> Void
    let onSwitchCamera: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.07, green: 0.11, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                if call.type == .video {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 32)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                if let remoteVideoTrack {
                                    WebRTCVideoView(track: remoteVideoTrack)
                                        .clipShape(RoundedRectangle(cornerRadius: 32))
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: call.isCameraEnabled ? "video.fill" : "video.slash.fill")
                                            .font(.system(size: 42))
                                        Text(call.status == .connected ? "Ожидание видео собеседника..." : "Подключение видео...")
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .callerGlassCard(cornerRadius: 32, tint: .blue)

                        if let localVideoTrack, call.isCameraEnabled {
                            WebRTCVideoView(track: localVideoTrack, mirror: call.isUsingFrontCamera)
                                .frame(width: 120, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                }
                                .padding(18)
                        }
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(.white, .green)
                }

                VStack(spacing: 8) {
                    Text(call.participant.name)
                        .font(.largeTitle.bold())
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(statusText(at: context.date))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 18) {
                    CallControlButton(systemName: call.isMuted ? "mic.slash.fill" : "mic.fill", isActive: call.isMuted, action: onToggleMute)
                    if call.type == .audio {
                        CallControlButton(systemName: call.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill", isActive: call.isSpeakerEnabled, action: onToggleSpeaker)
                    }
                    if call.type == .video {
                        CallControlButton(systemName: call.isCameraEnabled ? "video.fill" : "video.slash.fill", isActive: call.isCameraEnabled, action: onToggleCamera)
                        CallControlButton(systemName: "arrow.triangle.2.circlepath.camera.fill", isActive: false, action: onSwitchCamera)
                    }
                }

                LargeCallActionButton(systemName: "phone.down.fill", tint: .red, action: onEnd)
                    .padding(.bottom, 24)
            }
            .padding()
        }
    }

    private func statusText(at date: Date) -> String {
        switch call.status {
        case .idle:
            return "Ожидание"
        case .ringing:
            return "Вызов..."
        case .connecting:
            return "Подключение..."
        case .connected:
            if let startedAt = call.startedAt {
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.minute, .second]
                formatter.zeroFormattingBehavior = [.pad]
                let interval = max(0, date.timeIntervalSince(startedAt))
                return formatter.string(from: interval) ?? "Подключено"
            }
            return "Подключено"
        case .ended:
            return "Звонок завершён"
        case .failed:
            return "Ошибка подключения"
        }
    }
}
