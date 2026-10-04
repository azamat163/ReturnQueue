import Foundation

/// Owns ephemeral recovery copies, never the live archive or arbitrary caller paths.
public actor RecoveryFileService {
  private let directory: URL
  private var ownedURLs = Set<URL>()

  public init(directory: URL) {
    self.directory = directory
  }

  public func makeDestination() throws -> URL {
    guard directory.isFileURL, !directory.path.utf8.contains(0) else {
      throw ReturnPersistenceFailure.invalidDestination
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw ReturnPersistenceFailure.rawCopyFailed
    }
    let url = directory.appendingPathComponent("ReturnQueue-original-\(UUID().uuidString).json")
    ownedURLs.insert(url)
    return url
  }

  public func remove(_ url: URL) throws {
    guard ownedURLs.contains(url) else { throw ReturnPersistenceFailure.invalidDestination }
    do {
      try FileManager.default.removeItem(at: url)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      // A destination allocated before a failed copy can legitimately be absent.
    } catch {
      throw ReturnPersistenceFailure.rawCopyFailed
    }
    ownedURLs.remove(url)
  }
}
