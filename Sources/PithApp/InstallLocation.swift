import Foundation
import Security

/// Where the running Pith sits: in an Applications folder, translocated by Gatekeeper, or somewhere else.
enum InstallLocation: Equatable {
    case applications
    /// Anywhere else; `original` is where the bundle is.
    case elsewhere(original: URL)
    /// Run from the temporary path of App Translocation; `original` is where the bundle really is, `nil` if that is unknown.
    case translocated(original: URL?)

    var isApplications: Bool { self == .applications }

    /// The bundle's own path, the source of a move; `nil` when it is not known.
    var originalURL: URL? {
        switch self {
        case .applications: nil
        case .elsewhere(let url): url
        case .translocated(let url): url
        }
    }

    /// Whether `url` is in `/Applications` or `~/Applications`, in a subfolder too. Symbolic links are resolved first, so a
    /// link into `/Applications` counts and `/Applications.bak` does not.
    static func isInApplications(_ url: URL, home: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        for folder in [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")] {
            let prefix = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            if path.count > prefix.count, Array(path.prefix(prefix.count)) == prefix { return true }
        }
        return false
    }

    /// The place of a bundle at `bundleURL`. `translocation` answers for a translocated path with its original, or `nil` for a path
    /// that is not translocated; where the system cannot tell, a path with `/AppTranslocation/` is translocated and its original unknown.
    static func classify(bundleURL: URL, home: URL, translocation: @MainActor (URL) -> Translocation = Translocation.ask) -> InstallLocation {
        var source = bundleURL
        var translocated = false
        switch translocation(bundleURL) {
        case .translocated(let original):
            translocated = true
            if let original { source = original }
        case .notTranslocated:
            break
        case .unknown:
            translocated = bundleURL.pathComponents.contains("AppTranslocation")
        }
        let known = !translocated || source != bundleURL
        if known, isInApplications(source, home: home) { return .applications }
        if translocated { return .translocated(original: known ? source : nil) }
        return .elsewhere(original: source)
    }

    /// The place of the running Pith.
    static func current(bundle: Bundle = .main) -> InstallLocation {
        classify(bundleURL: bundle.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser)
    }
}

/// What App Translocation says of a path.
enum Translocation: Equatable {
    case notTranslocated
    /// The path is translocated; `original` is the real one, if the system gave it.
    case translocated(original: URL?)
    /// The system does not answer (its functions are missing).
    case unknown

    /// `SecTranslocateIsTranslocatedURL` and `SecTranslocateCreateOriginalPathForURL`: not in the Swift headers, found by name.
    static func ask(_ url: URL) -> Translocation {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
        typealias CreateOriginal = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let handle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let isSymbol = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return .unknown }
        let isTranslocated = unsafeBitCast(isSymbol, to: IsTranslocated.self)
        let createOriginal = unsafeBitCast(originalSymbol, to: CreateOriginal.self)
        var answer = false
        var error: Unmanaged<CFError>?
        guard isTranslocated(url as CFURL, &answer, &error) else {
            error?.release()
            return .unknown
        }
        guard answer else { return .notTranslocated }
        let original = createOriginal(url as CFURL, &error)?.takeRetainedValue()
        error?.release()
        return .translocated(original: original as URL?)
    }
}
