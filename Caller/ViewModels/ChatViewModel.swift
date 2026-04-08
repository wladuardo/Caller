import Combine
import Foundation
import UniformTypeIdentifiers

enum ChatScreenState: Equatable {
    case loading
    case content
    case empty
    case error(String)
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var screenState: ChatScreenState = .loading
    @Published var draft = ""
    @Published var errorMessage: String?
    @Published private(set) var isParticipantTyping = false
    @Published private(set) var selectedAttachment: ChatDraftAttachment?
    @Published private(set) var isSendingAttachment = false

    let currentUser: AppUser
    let participant: AppUser

    private let chatService: ChatServicing
    private let onAppear: (() -> Void)?
    private let onDisappear: (() -> Void)?
    private var observationTask: Task<Void, Never>?
    private var typingObservationTask: Task<Void, Never>?
    private var typingDebounceTask: Task<Void, Never>?
    private var lastReportedTypingState = false

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

    deinit {
        observationTask?.cancel()
        typingObservationTask?.cancel()
        typingDebounceTask?.cancel()
    }

    func startObserving() {
        guard observationTask == nil else { return }
        onAppear?()
        screenState = .loading
        startObservingTyping()

        observationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await chatService.prepareConversation(with: participant, currentUser: currentUser)
                try await chatService.markConversationAsRead(with: participant, currentUser: currentUser)
            } catch {
                let message = error.localizedDescription
                errorMessage = message
                screenState = .error(message)
            }

            for await messages in chatService.observeMessages(with: participant, currentUser: currentUser) {
                if Task.isCancelled {
                    break
                }
                self.messages = messages
                self.screenState = messages.isEmpty ? .empty : .content
                do {
                    try await chatService.markConversationAsRead(with: participant, currentUser: currentUser)
                } catch {
                    errorMessage = error.localizedDescription
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
        isParticipantTyping = false
        Task {
            try? await chatService.setTyping(false, with: participant, currentUser: currentUser)
        }
        onDisappear?()
    }

    func sendMessage() async {
        let messageText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentToSend = selectedAttachment
        guard !messageText.isEmpty || attachmentToSend != nil else { return }

        do {
            isSendingAttachment = attachmentToSend != nil
            try? await chatService.setTyping(false, with: participant, currentUser: currentUser)
            lastReportedTypingState = false
            try await chatService.sendMessage(messageText, attachment: attachmentToSend, to: participant, from: currentUser)
            draft = ""
            selectedAttachment = nil
            isSendingAttachment = false
        } catch {
            isSendingAttachment = false
            errorMessage = error.localizedDescription
        }
    }

    func setPhotoAttachment(data: Data) {
        selectedAttachment = ChatDraftAttachment(
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
            selectedAttachment = ChatDraftAttachment(
                kind: contentType.hasPrefix("image/") ? .image : .file,
                fileName: fileName,
                data: data,
                contentType: contentType
            )
        } catch {
            errorMessage = "Не удалось прочитать файл."
        }
    }

    func removeAttachment() {
        selectedAttachment = nil
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
        errorMessage = nil
    }

    private func startObservingTyping() {
        typingObservationTask?.cancel()
        typingObservationTask = Task { [weak self] in
            guard let self else { return }

            for await isTyping in chatService.observeTypingStatus(with: participant, currentUser: currentUser) {
                if Task.isCancelled {
                    break
                }
                self.isParticipantTyping = isTyping
            }
        }
    }
}
