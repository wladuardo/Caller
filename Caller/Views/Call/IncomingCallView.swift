import SwiftUI

struct IncomingCallView: View {
    let call: CallSession
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.06, green: 0.10, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 18) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 110))
                        .foregroundStyle(.white, .blue)

                    VStack(spacing: 8) {
                        Text(call.participant.name)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(call.type == .video ? "Видеозвонок" : "Аудиозвонок")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .callerGlassCard(cornerRadius: 30, tint: call.type == .video ? .blue : .green)

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
