import AppKit
import AuthenticationServices
import Foundation

@MainActor
final class WebAuthenticationController: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    static let shared = WebAuthenticationController()

    private var session: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?

    func authenticate(using url: URL, callbackURLScheme: String) async throws -> URL {
        guard session == nil else {
            throw WebAuthenticationError.sessionAlreadyInProgress
        }
        guard
            let window =
                NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible })
        else {
            throw WebAuthenticationError.noPresentationAnchor
        }
        presentationAnchor = window
        let controller: WebAuthenticationController = self

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackURLScheme)
            ) { callbackURL, error in
                Task { @MainActor in
                    controller.finish()
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionError.errorDomain {
                            continuation.resume(
                                throwing: ASWebAuthenticationSessionError(_nsError: nsError))
                        } else {
                            continuation.resume(throwing: error)
                        }
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: WebAuthenticationError.missingCallbackURL)
                    }
                }
            }
            session.presentationContextProvider = self
            self.session = session

            guard session.start() else {
                finish()
                continuation.resume(throwing: WebAuthenticationError.failedToStart)
                return
            }
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            preconditionFailure("Web authentication started without a presentation anchor")
        }
        return presentationAnchor
    }

    private func finish() {
        session = nil
        presentationAnchor = nil
    }
}

private enum WebAuthenticationError: LocalizedError {
    case sessionAlreadyInProgress
    case noPresentationAnchor
    case failedToStart
    case missingCallbackURL

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyInProgress:
            "A sign-in session is already in progress."
        case .noPresentationAnchor:
            "No window is available to present sign-in."
        case .failedToStart:
            "The sign-in browser could not be started."
        case .missingCallbackURL:
            "The sign-in browser finished without a callback URL."
        }
    }
}
