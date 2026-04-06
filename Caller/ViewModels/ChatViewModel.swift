import Combine
import Foundation

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

    let currentUser: AppUser
    let participant: AppUser

    private let chatService: ChatServicing
    private let onAppear: (() -> Void)?
    private let onDisappear: (() -> Void)?
    private var observationTask: Task<Void, Never>?

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
    }

    func startObserving() {
        guard observationTask == nil else { return }
        onAppear?()
        screenState = .loading

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
        onDisappear?()
    }

    func sendMessage() async {
        let messageText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        do {
            try await chatService.sendMessage(messageText, to: participant, from: currentUser)
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
