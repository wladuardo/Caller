import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                TabView(selection: $viewModel.selectedIndex) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                        pageView(page)
                            .padding(.horizontal, 24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                indicators
                    .padding(.bottom, 18)

                primaryAction
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Circle()
                .fill(viewModel.currentPage.accent.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 20)
                .offset(x: -130, y: -260)
        }
        .overlay {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 26)
                .offset(x: 140, y: 260)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: viewModel.selectedIndex)
    }

    private var gradientColors: [Color] {
        switch viewModel.currentPage.id {
        case .mapFriends:
            return [Color.black, Color(red: 0.05, green: 0.11, blue: 0.2), Color(red: 0.03, green: 0.2, blue: 0.28)]
        case .callsAndVideo:
            return [Color.black, Color(red: 0.03, green: 0.08, blue: 0.2), Color(red: 0.03, green: 0.14, blue: 0.34)]
        case .messenger:
            return [Color.black, Color(red: 0.04, green: 0.12, blue: 0.14), Color(red: 0.03, green: 0.25, blue: 0.2)]
        }
    }

    private var header: some View {
        HStack {
            Button {
                viewModel.skip(onFinish: onFinish)
            } label: {
                Text(viewModel.isLastPage ? "Завершить" : "Пропустить")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(viewModel.canSkip || viewModel.isLastPage ? 1 : 0)

            Spacer()
        }
    }

    private func pageView(_ page: OnboardingViewModel.Page) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 16)

            icon(page: page)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: 420)

            if let permissionMessage = page.permissionMessage {
                permissionContextCard(permissionMessage, accent: page.accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            Spacer(minLength: 8)
        }
    }

    private func permissionContextCard(_ message: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .callerGlassCard(cornerRadius: 20, tint: accent, showsShadow: false)
    }

    private func icon(page: OnboardingViewModel.Page) -> some View {
        ZStack {
            Circle()
                .fill(page.accent.opacity(0.22))
                .frame(width: 164, height: 164)
                .blur(radius: 2)

            Image(systemName: page.systemImage)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .callerGlassCard(cornerRadius: 36, tint: page.accent)
        }
        .shadow(color: page.accent.opacity(0.22), radius: 24, y: 12)
    }

    private var indicators: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == viewModel.selectedIndex ? Color.white : Color.white.opacity(0.26))
                    .frame(width: index == viewModel.selectedIndex ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: viewModel.selectedIndex)
            }
        }
    }

    private var primaryAction: some View {
        Button {
            Task {
                await viewModel.handlePrimaryAction(onFinish: onFinish)
            }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isRequestInFlight {
                    ProgressView()
                        .tint(.white)
                }

                Text(viewModel.currentPage.actionTitle)
                    .font(.headline.weight(.semibold))

                if !viewModel.isRequestInFlight {
                    Image(systemName: viewModel.isLastPage ? "checkmark" : "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .callerGlassButtonSurface(cornerRadius: 18, tint: viewModel.currentPage.accent)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRequestInFlight)
    }
}
