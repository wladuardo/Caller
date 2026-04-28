import SwiftUI

struct CallControlButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .callerGlassButtonSurface(
                    cornerRadius: 999,
                    tint: isActive ? .white : .gray
                )
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
                .callerGlassButtonSurface(cornerRadius: 999, tint: tint)
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
                .callerGlassButtonSurface(cornerRadius: 999, tint: tint)
        }
        .buttonStyle(.plain)
    }
}
