import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isComposerFocused: Bool
    
    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            messageList
                .safeAreaInset(edge: .bottom) {
                    composer
                }
                .background {
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.07, green: 0.1, blue: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .onTapGesture {
                        isComposerFocused = false
                    }
                }
        }
        .navigationTitle("Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(viewModel.participant.displayName)
                        .font(.headline)
                    Text(viewModel.participant.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            viewModel.startObserving()
        }
        .onAppear {
            isComposerFocused = true
        }
        .onDisappear {
            viewModel.stopObserving()
        }
        .alert("Чат", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("ОК", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "Что-то пошло не так.")
        }
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageBubble(
                            message: message,
                            isOutgoing: message.isOutgoing(for: viewModel.currentUser.id)
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    isComposerFocused = false
                }
            )
            .onChange(of: viewModel.screenState) { _, state in
                guard state == .content else { return }
                scrollToBottom(using: proxy, animated: true)
            }
            .onChange(of: viewModel.messages.last?.id) { oldValue, newValue in
                guard viewModel.screenState == .content,
                      oldValue != nil,
                      newValue != nil,
                      oldValue != newValue else {
                    return
                }
                scrollToBottom(using: proxy, animated: true)
            }
            .onChange(of: isComposerFocused) { _, isFocused in
                guard isFocused, viewModel.screenState == .content else { return }
                scrollToBottom(using: proxy, animated: true)
            }
            .overlay {
                switch viewModel.screenState {
                case .loading:
                    ProgressView()
                        .tint(.white)
                case .empty:
                    ContentUnavailableView(
                        "Сообщений пока нет",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Отправьте первое сообщение, чтобы начать переписку.")
                    )
                    .foregroundStyle(.white.opacity(0.8))
                case .error(let message):
                    ContentUnavailableView(
                        "Не удалось загрузить чат",
                        systemImage: "exclamationmark.bubble",
                        description: Text(message)
                    )
                    .foregroundStyle(.white.opacity(0.8))
                case .content:
                    EmptyView()
                }
            }
        }
    }
    
    private var composer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "message")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isComposerFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .callerGlassCard(cornerRadius: 22, tint: .cyan)
            
            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .callerGlassButtonSurface(
                        cornerRadius: 999,
                        tint: viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .gray
                        : .blue
                    )
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.clear)
    }
    
    private func scrollToBottom(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let lastID = viewModel.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}
