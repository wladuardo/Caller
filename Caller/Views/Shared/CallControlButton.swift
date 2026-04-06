import SwiftUI

struct CallControlButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(isActive ? Color.white.opacity(0.22) : Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct LargeCallActionButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ActionChip: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.92), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
