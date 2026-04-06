import AVFoundation
import Combine
import CoreMedia
import Foundation
import WebRTC

protocol CallServicing: AnyObject {
    var activeCallPublisher: AnyPublisher<CallSession?, Never> { get }
    var incomingCallPublisher: AnyPublisher<CallSession?, Never> { get }
    var errorPublisher: AnyPublisher<CallError?, Never> { get }
    var localVideoTrackPublisher: AnyPublisher<RTCVideoTrack?, Never> { get }
    var remoteVideoTrackPublisher: AnyPublisher<RTCVideoTrack?, Never> { get }
    func startCall(with user: AppUser, type: CallType, currentUser: AppUser) async
    func acceptIncomingCall(currentUser: AppUser) async
    func declineIncomingCall(currentUser: AppUser) async
    func endCall(currentUser: AppUser) async
    func toggleMute()
    func toggleSpeaker()
    func toggleCamera()
    func switchCamera()
    func connect(currentUser: AppUser) async
}

final class WebRTCCallService: NSObject, CallServicing {
    private let signalingService: SignalingServicing
    private let contactService: ContactServicing
    private let permissionService: PermissionServicing
    private let logger: Logger
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let audioSession = AVAudioSession.sharedInstance()

    private let activeCallSubject = CurrentValueSubject<CallSession?, Never>(nil)
    private let incomingCallSubject = CurrentValueSubject<CallSession?, Never>(nil)
    private let errorSubject = CurrentValueSubject<CallError?, Never>(nil)
    private let localVideoTrackSubject = CurrentValueSubject<RTCVideoTrack?, Never>(nil)
    private let remoteVideoTrackSubject = CurrentValueSubject<RTCVideoTrack?, Never>(nil)

    private var peerConnection: RTCPeerConnection?
    private var currentUser: AppUser?
    private var audioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var signalingTask: Task<Void, Never>?
    private var pendingIncomingOffer: RTCSessionDescription?

    var activeCallPublisher: AnyPublisher<CallSession?, Never> { activeCallSubject.eraseToAnyPublisher() }
    var incomingCallPublisher: AnyPublisher<CallSession?, Never> { incomingCallSubject.eraseToAnyPublisher() }
    var errorPublisher: AnyPublisher<CallError?, Never> { errorSubject.eraseToAnyPublisher() }
    var localVideoTrackPublisher: AnyPublisher<RTCVideoTrack?, Never> { localVideoTrackSubject.eraseToAnyPublisher() }
    var remoteVideoTrackPublisher: AnyPublisher<RTCVideoTrack?, Never> { remoteVideoTrackSubject.eraseToAnyPublisher() }

    init(
        signalingService: SignalingServicing,
        contactService: ContactServicing,
        permissionService: PermissionServicing,
        logger: Logger
    ) {
        self.signalingService = signalingService
        self.contactService = contactService
        self.permissionService = permissionService
        self.logger = logger
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    func connect(currentUser: AppUser) async {
        self.currentUser = currentUser

        do {
            try await signalingService.connect(userID: currentUser.id)
            logger.info("Connected signaling for \(currentUser.email)")
            observeSignalingMessages()
        } catch {
            errorSubject.send(.signalingUnavailable)
        }
    }

    func startCall(with user: AppUser, type: CallType, currentUser: AppUser) async {
        self.currentUser = currentUser

        guard await validatePermissions(for: type) else { return }

        let session = CallSession(
            id: UUID(),
            participant: CallParticipant(id: user.id, name: user.displayName, email: user.email),
            direction: .outgoing,
            type: type,
            status: .connecting,
            isMuted: false,
            isSpeakerEnabled: type == .video,
            isCameraEnabled: type == .video,
            isUsingFrontCamera: true,
            startedAt: nil
        )
        activeCallSubject.send(session)

        do {
            try await configureAudioSession(useSpeaker: session.isSpeakerEnabled)
            let peerConnection = try createPeerConnection()
            self.peerConnection = peerConnection
            try await prepareLocalMedia(for: type, callID: session.id)

            let offer = try await createOffer(on: peerConnection, type: type)
            try await setLocalDescription(offer, on: peerConnection)

            updateActiveCall { $0.status = .ringing }

            try await signalingService.send(
                SignalingMessage(
                    callID: session.id,
                    fromUserID: currentUser.id,
                    toUserID: user.id,
                    payload: .offer(sdp: offer.sdp, type: type),
                    sentAt: .now
                )
            )
        } catch let error as CallError {
            errorSubject.send(error)
            teardownMedia()
        } catch {
            logger.error("Failed to start call: \(error.localizedDescription)")
            errorSubject.send(.general("Unable to start the call."))
            teardownMedia()
        }
    }

    func acceptIncomingCall(currentUser: AppUser) async {
        self.currentUser = currentUser

        guard var incoming = incomingCallSubject.value,
              let remoteOffer = pendingIncomingOffer else { return }
        guard await validatePermissions(for: incoming.type) else { return }

        do {
            try await configureAudioSession(useSpeaker: incoming.type == .video)
            let peerConnection = try createPeerConnection()
            self.peerConnection = peerConnection
            try await prepareLocalMedia(for: incoming.type, callID: incoming.id)
            try await setRemoteDescription(remoteOffer, on: peerConnection)

            let answer = try await createAnswer(on: peerConnection, type: incoming.type)
            try await setLocalDescription(answer, on: peerConnection)

            incoming.status = .connecting
            incoming.startedAt = .now
            activeCallSubject.send(incoming)
            incomingCallSubject.send(nil)

            try await signalingService.send(
                SignalingMessage(
                    callID: incoming.id,
                    fromUserID: currentUser.id,
                    toUserID: incoming.participant.id,
                    payload: .answer(sdp: answer.sdp),
                    sentAt: .now
                )
            )
        } catch let error as CallError {
            errorSubject.send(error)
            teardownMedia()
        } catch {
            logger.error("Failed to accept call: \(error.localizedDescription)")
            errorSubject.send(.general("Unable to accept the call."))
            teardownMedia()
        }
    }

    func declineIncomingCall(currentUser: AppUser) async {
        guard let incoming = incomingCallSubject.value else { return }
        incomingCallSubject.send(nil)
        pendingIncomingOffer = nil

        do {
            try await signalingService.send(
                SignalingMessage(
                    callID: incoming.id,
                    fromUserID: currentUser.id,
                    toUserID: incoming.participant.id,
                    payload: .hangup,
                    sentAt: .now
                )
            )
        } catch {
            errorSubject.send(.signalingUnavailable)
        }
    }

    func endCall(currentUser: AppUser) async {
        if let activeCall = activeCallSubject.value {
            do {
                try await signalingService.send(
                    SignalingMessage(
                        callID: activeCall.id,
                        fromUserID: currentUser.id,
                        toUserID: activeCall.participant.id,
                        payload: .hangup,
                        sentAt: .now
                    )
                )
            } catch {
                errorSubject.send(.signalingUnavailable)
            }
        }

        if var activeCall = activeCallSubject.value {
            activeCall.status = .ended
            activeCallSubject.send(activeCall)
        }

        teardownMedia()
        activeCallSubject.send(nil)
        incomingCallSubject.send(nil)
    }

    func toggleMute() {
        guard let audioTrack else { return }
        audioTrack.isEnabled.toggle()
        updateActiveCall { $0.isMuted = !audioTrack.isEnabled }
    }

    func toggleSpeaker() {
        let speakerEnabled = !(activeCallSubject.value?.isSpeakerEnabled ?? false)

        Task { @MainActor in
            do {
                try await configureAudioSession(useSpeaker: speakerEnabled)
                self.updateActiveCall { $0.isSpeakerEnabled = speakerEnabled }
            } catch {
                self.errorSubject.send(.general("Unable to update audio route."))
            }
        }
    }

    func toggleCamera() {
        guard let localVideoTrack else { return }
        localVideoTrack.isEnabled.toggle()
        updateActiveCall { $0.isCameraEnabled = localVideoTrack.isEnabled }
    }

    func switchCamera() {
        guard let videoCapturer else { return }

        Task { @MainActor in
            do {
                try await switchCaptureDevice(on: videoCapturer)
                self.updateActiveCall { $0.isUsingFrontCamera.toggle() }
            } catch {
                self.errorSubject.send(.general("Unable to switch camera."))
            }
        }
    }

    private func observeSignalingMessages() {
        signalingTask?.cancel()
        signalingTask = Task { [weak self] in
            guard let self else { return }

            for await message in signalingService.incomingMessages {
                await self.handle(message)
            }
        }
    }

    @MainActor
    private func handle(_ message: SignalingMessage) async {
        switch message.payload {
        case .offer(let sdp, let type):
            pendingIncomingOffer = RTCSessionDescription(type: .offer, sdp: sdp)
            let participant = await resolveParticipant(for: message.fromUserID)

            incomingCallSubject.send(
                CallSession(
                    id: message.callID,
                    participant: participant,
                    direction: .incoming,
                    type: type,
                    status: .ringing,
                    isMuted: false,
                    isSpeakerEnabled: type == .video,
                    isCameraEnabled: type == .video,
                    isUsingFrontCamera: true,
                    startedAt: nil
                )
            )
        case .answer(let sdp):
            guard let peerConnection else { return }

            do {
                try await setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp), on: peerConnection)
                updateActiveCall {
                    $0.status = .connected
                    $0.startedAt = $0.startedAt ?? .now
                }
            } catch {
                logger.error("Failed to apply remote answer: \(error.localizedDescription)")
                errorSubject.send(.transportFailure)
            }
        case .iceCandidate(let candidate):
            guard let peerConnection else { return }

            do {
                try await addIceCandidate(
                    RTCIceCandidate(
                        sdp: candidate.sdp,
                        sdpMLineIndex: Int32(candidate.sdpMLineIndex),
                        sdpMid: candidate.sdpMid
                    ),
                    on: peerConnection
                )
            } catch {
                logger.error("Failed to add ICE candidate: \(error.localizedDescription)")
            }
        case .hangup:
            if var activeCall = activeCallSubject.value {
                activeCall.status = .ended
                activeCallSubject.send(activeCall)
            }
            teardownMedia()
            activeCallSubject.send(nil)
            incomingCallSubject.send(nil)
        }
    }

    private func validatePermissions(for type: CallType) async -> Bool {
        let microphoneGranted = await permissionService.requestMicrophoneAccess()
        guard microphoneGranted else {
            errorSubject.send(.permissionDenied(permissionService.deniedMessage(for: .microphone)))
            return false
        }

        if type == .video {
            let cameraGranted = await permissionService.requestCameraAccess()
            guard cameraGranted else {
                errorSubject.send(.permissionDenied(permissionService.deniedMessage(for: .camera)))
                return false
            }
        }

        return true
    }

    private func resolveParticipant(for userID: String) async -> CallParticipant {
        do {
            if let user = try await contactService.fetchUser(id: userID) {
                return CallParticipant(id: user.id, name: user.displayName, email: user.email)
            }
        } catch {
            logger.error("Failed to resolve caller profile: \(error.localizedDescription)")
        }

        return CallParticipant(
            id: userID,
            name: "Unknown Caller",
            email: ""
        )
    }

    private func createPeerConnection() throws -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )

        guard let peerConnection = peerConnectionFactory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw CallError.transportFailure
        }

        return peerConnection
    }

    private func prepareLocalMedia(for type: CallType, callID: UUID) async throws {
        let audioSource = peerConnectionFactory.audioSource(with: nil)
        let audioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio-\(callID.uuidString)")
        self.audioTrack = audioTrack
        _ = peerConnection?.add(audioTrack, streamIds: ["stream-\(callID.uuidString)"])

        guard type == .video else {
            localVideoTrack = nil
            localVideoTrackSubject.send(nil)
            return
        }

        let videoSource = peerConnectionFactory.videoSource()
        let videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video-\(callID.uuidString)")
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)

        _ = peerConnection?.add(videoTrack, streamIds: ["stream-\(callID.uuidString)"])
        localVideoTrack = videoTrack
        videoCapturer = capturer
        localVideoTrackSubject.send(videoTrack)

        try await startCapture(on: capturer, preferredFrontCamera: true)
    }

    private func teardownMedia() {
        pendingIncomingOffer = nil
        peerConnection?.close()
        peerConnection = nil
        videoCapturer?.stopCapture()
        videoCapturer = nil
        audioTrack = nil
        localVideoTrack = nil
        localVideoTrackSubject.send(nil)
        remoteVideoTrackSubject.send(nil)
    }

    private func updateActiveCall(_ transform: (inout CallSession) -> Void) {
        guard var activeCall = activeCallSubject.value else { return }
        transform(&activeCall)
        activeCallSubject.send(activeCall)
    }

    private func configureAudioSession(useSpeaker: Bool) async throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoChat,
            options: useSpeaker ? [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker] : [.allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try audioSession.setActive(true)
        try audioSession.overrideOutputAudioPort(useSpeaker ? .speaker : .none)
    }

    private func startCapture(on capturer: RTCCameraVideoCapturer, preferredFrontCamera: Bool) async throws {
        guard let device = selectCaptureDevice(preferredFrontCamera: preferredFrontCamera) else {
            throw CallError.general("No camera device is available.")
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.max(by: { pixelCount(for: $0) < pixelCount(for: $1) }) else {
            throw CallError.general("No supported camera format found.")
        }

        let fps = max(format.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate) }.max() ?? 30, 30)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: device, format: format, fps: fps) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func switchCaptureDevice(on capturer: RTCCameraVideoCapturer) async throws {
        let preferredFrontCamera = !(activeCallSubject.value?.isUsingFrontCamera ?? true)
        guard let device = selectCaptureDevice(preferredFrontCamera: preferredFrontCamera) else {
            throw CallError.general("No camera device is available.")
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.max(by: { pixelCount(for: $0) < pixelCount(for: $1) }) else {
            throw CallError.general("No supported camera format found.")
        }

        let fps = max(format.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate) }.max() ?? 30, 30)
        await capturer.stopCapture()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: device, format: format, fps: fps) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func selectCaptureDevice(preferredFrontCamera: Bool) -> AVCaptureDevice? {
        let devices = RTCCameraVideoCapturer.captureDevices()
        let preferredPosition: AVCaptureDevice.Position = preferredFrontCamera ? .front : .back
        return devices.first(where: { $0.position == preferredPosition }) ?? devices.first
    }

    private func pixelCount(for format: AVCaptureDevice.Format) -> Int32 {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return dimensions.width * dimensions.height
    }

    private func createOffer(on peerConnection: RTCPeerConnection, type: CallType) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: type == .video ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
            ],
            optionalConstraints: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: error ?? CallError.transportFailure)
                }
            }
        }
    }

    private func createAnswer(on peerConnection: RTCPeerConnection, type: CallType) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: type == .video ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
            ],
            optionalConstraints: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: error ?? CallError.transportFailure)
                }
            }
        }
    }

    private func setLocalDescription(_ sdp: RTCSessionDescription, on peerConnection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setRemoteDescription(_ sdp: RTCSessionDescription, on peerConnection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func addIceCandidate(_ candidate: RTCIceCandidate, on peerConnection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

extension WebRTCCallService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        logger.info("Signaling state changed: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let videoTrack = stream.videoTracks.first {
            remoteVideoTrackSubject.send(videoTrack)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        logger.info("Remote stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.info("Peer connection should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.info("ICE state changed: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.info("ICE gathering state changed: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let currentUser, let activeCall = activeCallSubject.value else { return }

        Task {
            do {
                try await signalingService.send(
                    SignalingMessage(
                        callID: activeCall.id,
                        fromUserID: currentUser.id,
                        toUserID: activeCall.participant.id,
                        payload: .iceCandidate(
                            IceCandidatePayload(
                                sdp: candidate.sdp,
                                sdpMLineIndex: Int32(candidate.sdpMLineIndex),
                                sdpMid: candidate.sdpMid
                            )
                        ),
                        sentAt: .now
                    )
                )
            } catch {
                await MainActor.run {
                    self.errorSubject.send(.signalingUnavailable)
                }
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.info("ICE candidates removed: \(candidates.count)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.info("Data channel opened: \(dataChannel.label)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        switch newState {
        case .connected:
            updateActiveCall {
                $0.status = .connected
                $0.startedAt = $0.startedAt ?? .now
            }
        case .connecting:
            updateActiveCall { $0.status = .connecting }
        case .disconnected, .failed:
            updateActiveCall { $0.status = .failed }
            errorSubject.send(.transportFailure)
        case .closed:
            updateActiveCall { $0.status = .ended }
        case .new:
            break
        @unknown default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
            remoteVideoTrackSubject.send(videoTrack)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        if rtpReceiver.track is RTCVideoTrack {
            remoteVideoTrackSubject.send(nil)
        }
    }
}
