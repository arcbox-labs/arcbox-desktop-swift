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
    private var continuation: CheckedContinuation<URL, Error>?
    private var isTerminating = false

    func authenticate(using url: URL, callbackURLScheme: String) async throws -> URL {
        guard !isTerminating else {
            throw Self.canceledLoginError
        }
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
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackURLScheme)
            ) { callbackURL, error in
                Task { @MainActor in
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionError.errorDomain {
                            controller.finish(
                                with: .failure(
                                    ASWebAuthenticationSessionError(_nsError: nsError)))
                        } else {
                            controller.finish(with: .failure(error))
                        }
                    } else if let callbackURL {
                        controller.finish(with: .success(callbackURL))
                    } else {
                        controller.finish(
                            with: .failure(WebAuthenticationError.missingCallbackURL))
                    }
                }
            }
            session.presentationContextProvider = self
            self.session = session

            guard session.start() else {
                finish(with: .failure(WebAuthenticationError.failedToStart))
                return
            }
        }
    }

    func cancelForTermination() {
        isTerminating = true
        session?.cancel()
        finish(with: .failure(Self.canceledLoginError))
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            preconditionFailure("Web authentication started without a presentation anchor")
        }
        return presentationAnchor
    }

    private func finish(with result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session = nil
        presentationAnchor = nil
        continuation.resume(with: result)
    }

    private static var canceledLoginError: ASWebAuthenticationSessionError {
        ASWebAuthenticationSessionError(
            _nsError: NSError(
                domain: ASWebAuthenticationSessionError.errorDomain,
                code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
            ))
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
