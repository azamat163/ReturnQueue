#if DEBUG
  import Foundation

  /// Only constructed for an explicitly selected UUID directory inside the app container.
  public actor UITestFixtureService {
    private let repository: ReturnRepository
    private let backupURL: URL
    private let corruptOnLaunch: Bool
    private let repairOnRetry: Bool

    public init(directory: URL, corruptOnLaunch: Bool, repairOnRetry: Bool) {
      repository = ReturnRepository(fileURL: directory.appendingPathComponent("returns.json"))
      backupURL = directory.appendingPathComponent("test-original.json")
      self.corruptOnLaunch = corruptOnLaunch
      self.repairOnRetry = repairOnRetry
    }

    public func prepare() throws {
      guard corruptOnLaunch else { return }
      do {
        // A fresh test first creates a real record. No purchase fixtures are seeded here.
        guard let previous = try repository.readArchiveData() else { return }
        if !FileManager.default.fileExists(atPath: backupURL.path) {
          try ReturnRepository(fileURL: backupURL).writeAtomically(previous)
        }
        try repository.writeAtomically(Data("ReturnQueue isolated test corruption".utf8))
      } catch {
        throw ReturnPersistenceFailure.writeFailed
      }
    }

    public func repairForRetry() throws {
      guard repairOnRetry else { return }
      do {
        guard let original = try ReturnRepository(fileURL: backupURL).readArchiveData() else {
          return
        }
        try repository.writeAtomically(original)
      } catch {
        throw ReturnPersistenceFailure.writeFailed
      }
    }
  }
#endif
