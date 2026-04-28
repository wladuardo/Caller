import Foundation
import Observation
import UniformTypeIdentifiers

enum ChatScreenState: Equatable {
    case loading
    case content
    case empty
    case error(String)
}

@MainActor
@Observable
final class ChatViewModel: Store {
    var state = State()

    let currentUser: AppUser
    let participant: AppUser

    private let chatService: ChatServicing
    private let onAppear: (() -> Void)?
    private let onDisappear: (() -> Void)?
    private var observationTask: Task<Void, Never>?
    private var typingObservationTask: Task<Void, Never>?
    private var typingDebounceTask: Task<Void, Never>?
    private var delayedLoadingTask: Task<Void, Never>?
    private var lastReportedTypingState = false
    private var hasResolvedInitialLoad = false

    init(
        currentUser: AppUser,
        participant: AppUser,
        chatService: ChatServicing,
        onAppear: (() -> Void)? = nil,
        onDisappear: (() -> Void)? = nil
    ) {
        self.currentUser = currentUser
        self.participant = participant
        self.chatService = chatService
        self.onAppear = onAppear
        self.onDisappear = onDisappear
    }

    var messages: [ChatMessage] {
        state.messages
    }

    var screenState: ChatScreenState {
        state.screenState
    }

    var draft: String {
        get { state.draft }
        set { state.draft = newValue }
    }

    var errorMessage: String? {
        get { state.errorMessage }
        set { state.errorMessage = newValue }
    }

    var isParticipantTyping: Bool {
        state.isParticipantTyping
    }

    var selectedAttachment: ChatDraftAttachment? {
        state.selectedAttachment
    }

    var isSendingAttachment: Bool {
        state.isSendingAttachment
    }

    var isShowingDelayedLoader: Bool {
        state.isShowingDelayedLoader
    }

    func trigger(_ input: Input) async {
        switch input {
        case .startObserving:
            startObserving()
        case .stopObserving:
            stopObserving()
        case .sendMessage:
            await sendMessage()
        case .setDraft(let draft):
            self.draft = draft
        case .draftChanged(let draft):
            handleDraftChanged(draft)
        case .setPhotoAttachment(let data):
            setPhotoAttachment(data: data)
        case .setFileAttachment(let url):
            setFileAttachment(fileURL: url)
        case .fileAttachmentSelectionFailed:
            errorMessage = "Не удалось выбрать файл."
        case .removeAttachment:
            removeAttachment()
        case .dismissError:
            dismissError()
        case .setErrorMessage(let message):
            errorMessage = message
        }
    }

    func startObserving() {
        guard observationTask == nil else { return }
        onAppear?()
        delayedLoadingTask?.cancel()
        state.isShowingDelayedLoader = false
        hasResolvedInitialLoad = false
        startObservingTyping()

        observationTask = Task { [weak self] in
            guard let self else { return }

            let cachedMessages = await chatService.cachedMessages(with: participant, currentUser: currentUser)
            if Task.isCancelled { return }

            state.messages = cachedMessages
            state.screenState = cachedMessages.isEmpty ? .empty : .content

            if cachedMessages.isEmpty {
                scheduleDelayedLoader()
            } else {
                hasResolvedInitialLoad = true
            }

            do {
                try await chatService.prepareConversation(with: participant, currentUser: currentUser)
                try await chatService.markConversationAsRead(with: participant, currentUser: currentUser)
            } catch {
                delayedLoadingTask?.cancel()
                state.isShowingDelayedLoader = false
                let message = error.localizedDescription
                state.errorMessage = message
                state.screenState = .error(message)
            }

            for await messages in chatService.observeMessages(with: participant, currentUser: currentUser) {
                if Task.isCancelled {
                    break
                }
                hasResolvedInitialLoad = true
                delayedLoadingTask?.cancel()
                state.isShowingDelayedLoader = false
                state.messages = messages
                state.screenState = messages.isEmpty ? .empty : .content
                do {
                    try await chatService.markConversationAsRead(with: participant, currentUser: currentUser)
                } catch {
                    state.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        typingObservationTask?.cancel()
        typingObservationTask = nil
        typingDebounceTask?.cancel()
        typingDebounceTask = nil
        delayedLoadingTask?.cancel()
        delayedLoadingTask = nil
        state.isShowingDelayedLoader = false
        hasResolvedInitialLoad = false
        state.isParticipantTyping = false
        Task {
            try? await chatService.setTyping(false, with: participant, currentUser: currentUser)
        }
        onDisappear?()
    }

    func sendMessage() async {
        let messageText = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentToSend = state.selectedAttachment
        guard !messageText.isEmpty || attachmentToSend != nil else { return }

        do {
            state.isSendingAttachment = attachmentToSend != nil
            try? await chatService.setTyping(false, with: participant, currentUser: currentUser)
            lastReportedTypingState = false
            try await chatService.sendMessage(messageText, attachment: attachmentToSend, to: participant, from: currentUser)
            state.draft = ""
            state.selectedAttachment = nil
            state.isSendingAttachment = false
        } catch {
            state.isSendingAttachment = false
            state.errorMessage = error.localizedDescription
        }
    }

    func setPhotoAttachment(data: Data) {
        state.selectedAttachment = ChatDraftAttachment(
            kind: .image,
            fileName: "photo-\(Int(Date().timeIntervalSince1970)).jpg",
            data: data,
            contentType: "image/jpeg"
        )
    }

    func setFileAttachment(fileURL: URL) {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            state.selectedAttachment = ChatDraftAttachment(
                kind: contentType.hasPrefix("image/") ? .image : .file,
                fileName: fileName,
                data: data,
                contentType: contentType
            )
        } catch {
            state.errorMessage = "Не удалось прочитать файл."
        }
    }

    func removeAttachment() {
        state.selectedAttachment = nil
    }

    func handleDraftChanged(_ newValue: String) {
        let isTypingNow = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isTypingNow != lastReportedTypingState {
            lastReportedTypingState = isTypingNow
            Task {
                try? await chatService.setTyping(isTypingNow, with: participant, currentUser: currentUser)
            }
        }

        typingDebounceTask?.cancel()
        guard isTypingNow else { return }

        typingDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !Task.isCancelled else { return }
            self.lastReportedTypingState = false
            try? await self.chatService.setTyping(false, with: self.participant, currentUser: self.currentUser)
        }
    }

    func dismissError() {
        state.errorMessage = nil
    }

    private func scheduleDelayedLoader() {
        delayedLoadingTask?.cancel()
        delayedLoadingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled, !hasResolvedInitialLoad, state.messages.isEmpty else {
                return
            }
            state.isShowingDelayedLoader = true
        }
    }

    private func startObservingTyping() {
        typingObservationTask?.cancel()
        typingObservationTask = Task { [weak self] in
            guard let self else { return }

            for await isTyping in chatService.observeTypingStatus(with: participant, currentUser: currentUser) {
                if Task.isCancelled {
                    break
                }
                self.state.isParticipantTyping = isTyping
            }
        }
    }
}

extension ChatViewModel {
    struct State {
        var messages: [ChatMessage] = []
        var screenState: ChatScreenState = .loading
        var draft = ""
        var errorMessage: String?
        var isParticipantTyping = false
        var selectedAttachment: ChatDraftAttachment?
        var isSendingAttachment = false
        var isShowingDelayedLoader = false
    }

    enum Input: Sendable {
        case startObserving
        case stopObserving
        case sendMessage
        case setDraft(String)
        case draftChanged(String)
        case setPhotoAttachment(Data)
        case setFileAttachment(URL)
        case fileAttachmentSelectionFailed
        case removeAttachment
        case dismissError
        case setErrorMessage(String)
    }
}
