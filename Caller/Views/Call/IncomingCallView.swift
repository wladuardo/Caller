import SwiftUI

struct IncomingCallView: View {
    let call: CallSession
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(.white, .blue)
                Text(call.participant.name)
                    .font(.largeTitle.bold())
                Text(call.type == .video ? "Видеозвонок" : "Аудиозвонок")
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 28) {
                    LargeCallActionButton(systemName: "phone.down.fill", tint: .red, action: onDecline)
                    LargeCallActionButton(systemName: call.type == .video ? "video.fill" : "phone.fill", tint: .green, action: onAccept)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }
}
