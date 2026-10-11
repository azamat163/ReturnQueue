#if DEBUG
  import Foundation
  import ReturnQueueCore

  /// Only constructed for an explicitly selected UUID directory inside the app container.
  public actor UITestFixtureService {
    private let repository: ReturnRepository
    private let backupURL: URL
    private let corruptOnLaunch: Bool
    private let repairOnRetry: Bool
    private let documentsDirectory: URL?

    public init(
      directory: URL, corruptOnLaunch: Bool, repairOnRetry: Bool,
      documentsDirectory: URL? = nil
    ) {
      repository = ReturnRepository(fileURL: directory.appendingPathComponent("returns.json"))
      backupURL = directory.appendingPathComponent("test-original.json")
      self.corruptOnLaunch = corruptOnLaunch
      self.repairOnRetry = repairOnRetry
      self.documentsDirectory = documentsDirectory
    }

    public func prepare() throws {
      try prepareImportFiles()
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

    private func prepareImportFiles() throws {
      guard let documentsDirectory else { return }
      let destination = documentsDirectory.appendingPathComponent("Saved-return-backup.json")
      // Capture only a real, already committed UI-created archive. Preserve it across relaunches.
      guard !FileManager.default.fileExists(atPath: destination.path),
        let saved = try repository.readArchiveData()
      else { return }
      _ = try ReturnQueueCore.ArchiveCodec.decode(saved)
      try ReturnRepository(fileURL: destination).writeAtomically(saved)
      try ReturnRepository(
        fileURL: documentsDirectory.appendingPathComponent("Invalid-return-backup.json")
      ).writeAtomically(Data("ReturnQueue isolated malformed import fixture".utf8))
      try ReturnRepository(
        fileURL: documentsDirectory.appendingPathComponent("Empty-return-backup.json")
      ).writeAtomically(ArchiveCodec.encode([]))
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
