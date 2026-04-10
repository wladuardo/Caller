import PhotosUI
import QuickLook
import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isComposerFocused: Bool
    private let typingIndicatorID = "typing-indicator"
    private let unreadMessageCount: Int
    private let isNotificationsMuted: Bool
    private let onStartAudioCall: (() -> Void)?
    private let onStartVideoCall: (() -> Void)?
    private let onSetNotificationsMuted: ((Bool) async -> Void)?
    private let onRemoveFriend: (() async -> Void)?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPresentingFileImporter = false
    @State private var isPresentingAttachmentOptions = false
    @State private var isPresentingPhotosPicker = false
    @State private var attachmentPreview: ChatAttachmentPreview?
    @State private var isPreparingAttachmentPreview = false
    @State private var isShowingProfile = false
    @State private var keyboardAnimationDuration = 0.25
    @State private var keyboardScrollTask: Task<Void, Never>?
    
    init(
        viewModel: ChatViewModel,
        unreadMessageCount: Int = 0,
        isNotificationsMuted: Bool = false,
        onStartAudioCall: (() -> Void)? = nil,
        onStartVideoCall: (() -> Void)? = nil,
        onSetNotificationsMuted: ((Bool) async -> Void)? = nil,
        onRemoveFriend: (() async -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.unreadMessageCount = unreadMessageCount
        self.isNotificationsMuted = isNotificationsMuted
        self.onStartAudioCall = onStartAudioCall
        self.onStartVideoCall = onStartVideoCall
        self.onSetNotificationsMuted = onSetNotificationsMuted
        self.onRemoveFriend = onRemoveFriend
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
                Button {
                    isShowingProfile = true
                } label: {
                    VStack(spacing: 2) {
                        Text(viewModel.participant.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        ZStack {
                            Text(chatSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .opacity(viewModel.isParticipantTyping ? 0 : 1)
                                .offset(y: viewModel.isParticipantTyping ? -6 : 0)

                            Text("Печатает...")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.green.opacity(0.9))
                                .opacity(viewModel.isParticipantTyping ? 1 : 0)
                                .offset(y: viewModel.isParticipantTyping ? 0 : 6)
                        }
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isParticipantTyping)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingProfile = true
                } label: {
                    UserAvatarView(
                        user: viewModel.participant,
                        size: 34,
                        iconSize: 18,
                        iconTint: .white
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            viewModel.startObserving()
        }
        .onAppear {
            isComposerFocused = true
        }
        .onChange(of: viewModel.draft) { _, newValue in
            viewModel.handleDraftChanged(newValue)
        }
        .onDisappear {
            keyboardScrollTask?.cancel()
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
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: viewModel.isParticipantTyping)
        .overlay {
            if viewModel.isSendingAttachment || isPreparingAttachmentPreview {
                sendingMediaOverlay
            }
        }
        .fullScreenCover(item: imagePreviewBinding) { preview in
            imageAttachmentPreview(preview)
        }
        .sheet(item: filePreviewBinding) { preview in
            FileQuickLookPreview(fileURL: preview.fileURL, title: preview.title)
        }
        .sheet(isPresented: $isShowingProfile) {
            NavigationStack {
                FriendDetailsView(
                    user: viewModel.participant,
                    unreadMessageCount: unreadMessageCount,
                    isNotificationsMuted: isNotificationsMuted,
                    onOpenChat: {
                        isShowingProfile = false
                    },
                    onStartAudioCall: {
                        isShowingProfile = false
                        onStartAudioCall?()
                    },
                    onStartVideoCall: {
                        isShowingProfile = false
                        onStartVideoCall?()
                    },
                    onSetNotificationsMuted: { isMuted in
                        await onSetNotificationsMuted?(isMuted)
                    },
                    onRemoveFriend: {
                        guard let onRemoveFriend else { return }
                        await onRemoveFriend()
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            updateKeyboardAnimationDuration(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardAnimationDuration(from: notification)
        }
    }

    private var chatSubtitle: String {
        if let username = viewModel.participant.username,
           !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "@\(username)"
        }
        return viewModel.participant.email
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageBubble(
                            message: message,
                            isOutgoing: message.isOutgoing(for: viewModel.currentUser.id),
                            onAttachmentTap: previewAttachment
                        )
                        .id(message.id)
                    }

                    if viewModel.isParticipantTyping {
                        typingIndicator
                            .id(typingIndicatorID)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .leading)),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                )
                            )
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
                scheduleScrollToBottomAfterKeyboardAnimation(using: proxy)
            }
            .onChange(of: viewModel.isParticipantTyping) { _, isTyping in
                guard isTyping else { return }
                scrollToBottom(using: proxy, animated: true)
            }
            .overlay {
                if viewModel.isShowingDelayedLoader {
                    if viewModel.isShowingDelayedLoader {
                        ProgressView()
                            .tint(.white)
                    }
                } else {
                    switch viewModel.screenState {
                case .loading:
                    EmptyView()
                case .empty:
                    if !viewModel.isParticipantTyping {
                        ContentUnavailableView(
                            "Сообщений пока нет",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Отправьте первое сообщение, чтобы начать переписку.")
                        )
                        .foregroundStyle(.white.opacity(0.8))
                    }
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
    }
    
    private var composer: some View {
        VStack(spacing: 10) {
            if let attachment = viewModel.selectedAttachment {
                attachmentPreview(attachment)
            }

            HStack(spacing: 12) {
                Button {
                    isPresentingAttachmentOptions = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .callerGlassButtonSurface(cornerRadius: 999, tint: .teal)
                }
                .disabled(viewModel.isSendingAttachment)

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
                    ZStack {
                        if viewModel.isSendingAttachment {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .callerGlassButtonSurface(
                        cornerRadius: 999,
                        tint: canSendMessage ? .blue : .gray
                    )
                }
                .disabled(!canSendMessage || viewModel.isSendingAttachment)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.clear)
        .disabled(viewModel.isSendingAttachment)
        .confirmationDialog("Добавить вложение", isPresented: $isPresentingAttachmentOptions, titleVisibility: .visible) {
            Button("Фото") {
                isPresentingPhotosPicker = true
            }
            Button("Файл") {
                isPresentingFileImporter = true
            }
            Button("Отмена", role: .cancel) {}
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        viewModel.setPhotoAttachment(data: data)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $isPresentingPhotosPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.setFileAttachment(fileURL: url)
            case .failure:
                viewModel.errorMessage = "Не удалось выбрать файл."
            }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 8) {
                TypingDotsView()
                Text("Печатает...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 56)
        }
    }
    
    private func scrollToBottom(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let targetID: String
        if viewModel.isParticipantTyping {
            targetID = typingIndicatorID
        } else if let lastID = viewModel.messages.last?.id {
            targetID = lastID
        } else {
            return
        }

        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }

    private func scheduleScrollToBottomAfterKeyboardAnimation(using proxy: ScrollViewProxy) {
        keyboardScrollTask?.cancel()
        keyboardScrollTask = Task {
            let delay = max(keyboardAnimationDuration, 0)
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                scrollToBottom(using: proxy, animated: true)
            }
        }
    }

    private func updateKeyboardAnimationDuration(from notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        keyboardAnimationDuration = duration
    }

    private var canSendMessage: Bool {
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedAttachment != nil
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: ChatDraftAttachment) -> some View {
        HStack(spacing: 12) {
            Group {
                if attachment.kind == .image, let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: attachment.kind == .image ? "photo" : "doc.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.fileSize), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.removeAttachment()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .callerGlassCard(cornerRadius: 20, tint: .teal)
    }

    private var sendingMediaOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.15)

                Text("Отправка медиа...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .callerGlassCard(cornerRadius: 24, tint: .blue)
        }
        .transition(.opacity)
    }

    private var overlayTitle: String {
        if viewModel.isSendingAttachment {
            return "Отправка медиа..."
        }
        return "Подготовка вложения..."
    }

    private var imagePreviewBinding: Binding<ImageAttachmentPreview?> {
        Binding(
            get: {
                if case .image(let preview) = attachmentPreview {
                    return preview
                }
                return nil
            },
            set: { newValue in
                attachmentPreview = newValue.map { .image($0) }
            }
        )
    }

    private var filePreviewBinding: Binding<FileAttachmentPreview?> {
        Binding(
            get: {
                if case .file(let preview) = attachmentPreview {
                    return preview
                }
                return nil
            },
            set: { newValue in
                attachmentPreview = newValue.map { .file($0) }
            }
        )
    }

    private func previewAttachment(_ attachment: ChatAttachment) {
        switch attachment.kind {
        case .image:
            attachmentPreview = .image(
                ImageAttachmentPreview(
                    id: attachment.storagePath,
                    url: URL(string: attachment.downloadURL),
                    title: attachment.fileName
                )
            )
        case .file:
            guard let url = URL(string: attachment.downloadURL) else {
                viewModel.errorMessage = "Не удалось открыть вложение."
                return
            }

            Task {
                await MainActor.run {
                    isPreparingAttachmentPreview = true
                }

                do {
                    let localURL = try await RemoteFileCache.shared.localFileURL(
                        for: url,
                        preferredFileName: attachment.fileName
                    )
                    await MainActor.run {
                        isPreparingAttachmentPreview = false
                        attachmentPreview = .file(
                            FileAttachmentPreview(
                                id: attachment.storagePath,
                                fileURL: localURL,
                                title: attachment.fileName
                            )
                        )
                    }
                } catch {
                    await MainActor.run {
                        isPreparingAttachmentPreview = false
                        viewModel.errorMessage = "Не удалось открыть вложение."
                    }
                }
            }
        }
    }

    private func imageAttachmentPreview(_ preview: ImageAttachmentPreview) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            CachedRemoteImage(url: preview.url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } placeholder: {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }

            Button {
                attachmentPreview = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45), in: Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }
}

private struct TypingDotsView: View {
    @State private var activeDot = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(activeDot == index ? 0.95 : 0.35))
                    .frame(width: 6, height: 6)
                    .scaleEffect(activeDot == index ? 1 : 0.82)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(240))
                await MainActor.run {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
    }
}

private enum ChatAttachmentPreview: Identifiable {
    case image(ImageAttachmentPreview)
    case file(FileAttachmentPreview)

    var id: String {
        switch self {
        case .image(let preview):
            return preview.id
        case .file(let preview):
            return preview.id
        }
    }
}

private struct ImageAttachmentPreview: Identifiable {
    let id: String
    let url: URL?
    let title: String
}

private struct FileAttachmentPreview: Identifiable {
    let id: String
    let fileURL: URL
    let title: String
}

private struct FileQuickLookPreview: UIViewControllerRepresentable {
    let fileURL: URL
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL, title: title)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.title = title
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.fileURL = fileURL
        context.coordinator.title = title
        uiViewController.title = title
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var fileURL: URL
        var title: String

        init(fileURL: URL, title: String) {
            self.fileURL = fileURL
            self.title = title
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: fileURL, title: title)
        }
    }
}

private final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}
