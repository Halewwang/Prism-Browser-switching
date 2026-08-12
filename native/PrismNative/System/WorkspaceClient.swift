import AppKit
import CoreServices
import Foundation

@MainActor
protocol WorkspaceClient {
    func applicationURLs(toOpen url: URL) -> [URL]
    func open(_ url: URL, with applicationURL: URL) async throws
    func icon(for applicationURL: URL) -> NSImage
}

enum WorkspaceClientError: Error {
    case applicationUnavailable
    case rejected
    case system(Error)
}

enum WorkspaceOpenCompletion {
    case accepted
    case failure(WorkspaceClientError)
}

protocol WorkspaceOpenCompletionAdapting: Sendable {
    func resolve(didLaunchApplication: Bool, error: NSError?) -> WorkspaceOpenCompletion
}

struct WorkspaceOpenCompletionAdapter: WorkspaceOpenCompletionAdapting {
    func resolve(didLaunchApplication: Bool, error: NSError?) -> WorkspaceOpenCompletion {
        if let error {
            return .failure(classify(error))
        }
        return didLaunchApplication ? .accepted : .failure(.rejected)
    }

    private func classify(_ error: NSError) -> WorkspaceClientError {
        let errors = errorChain(startingAt: error)
        if errors.contains(where: isRejection) {
            return .rejected
        }
        if errors.contains(where: isApplicationUnavailable) {
            return .applicationUnavailable
        }
        return .system(error)
    }

    private func errorChain(startingAt error: NSError) -> [NSError] {
        var errors = [error]
        var index = 0
        while index < errors.count {
            let current = errors[index]
            if let underlyingError = current.userInfo[NSUnderlyingErrorKey] as? NSError,
               !errors.contains(where: {
                   $0.domain == underlyingError.domain && $0.code == underlyingError.code
               }) {
                errors.append(underlyingError)
            }
            index += 1
        }
        return errors
    }

    private func isRejection(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError {
            return true
        }
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(POSIXErrorCode.ECANCELED.rawValue) {
            return true
        }
        guard error.domain == NSOSStatusErrorDomain else { return false }
        return error.code == Int(kLSNoLaunchPermissionErr)
            || error.code == Int(kLSAppDoesNotClaimTypeErr)
    }

    private func isApplicationUnavailable(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            return [
                NSFileNoSuchFileError,
                NSFileReadNoPermissionError,
                NSFileReadInvalidFileNameError,
                NSFileReadCorruptFileError,
                NSFileReadNoSuchFileError
            ].contains(error.code)
        }
        if error.domain == NSPOSIXErrorDomain {
            return [
                Int(POSIXErrorCode.ENOENT.rawValue),
                Int(POSIXErrorCode.EACCES.rawValue),
                Int(POSIXErrorCode.EPERM.rawValue),
                Int(POSIXErrorCode.ENOTDIR.rawValue),
                Int(POSIXErrorCode.ENOEXEC.rawValue)
            ].contains(error.code)
        }
        guard error.domain == NSOSStatusErrorDomain else { return false }
        return [
            Int(kLSAppInTrashErr),
            Int(kLSIncompatibleApplicationVersionErr),
            Int(kLSNotAnApplicationErr),
            Int(kLSApplicationNotFoundErr),
            Int(kLSNoRegistrationInfoErr),
            Int(kLSIncompatibleSystemVersionErr),
            Int(kLSNoExecutableErr)
        ].contains(error.code)
    }
}

@MainActor
final class SystemWorkspaceClient: WorkspaceClient {
    private let completionAdapter: any WorkspaceOpenCompletionAdapting

    init(completionAdapter: any WorkspaceOpenCompletionAdapting = WorkspaceOpenCompletionAdapter()) {
        self.completionAdapter = completionAdapter
    }

    func applicationURLs(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    func open(_ url: URL, with applicationURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            throw WorkspaceClientError.applicationUnavailable
        }

        let completionAdapter = completionAdapter
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { application, error in
                switch completionAdapter.resolve(
                    didLaunchApplication: application != nil,
                    error: error as NSError?
                ) {
                case .accepted:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func icon(for applicationURL: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}
