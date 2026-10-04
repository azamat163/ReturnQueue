import Foundation
import ReturnQueueCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Bounded reads and same-directory atomic writes for the application's private archive.
public struct ReturnRepository: ReturnPersistence, Sendable {
  public enum WriteStage: Equatable, Sendable {
    case stage
    case protection
    case replacement
  }

  public let fileURL: URL
  private let failureInjector: @Sendable (WriteStage) throws -> Void
  private static let chunkSize = 64 * 1_024

  /// The synchronous seam can simulate each failure before the irreversible rename.
  public init(
    fileURL: URL,
    failureInjector: @escaping @Sendable (WriteStage) throws -> Void = { _ in }
  ) {
    self.fileURL = fileURL
    self.failureInjector = failureInjector
  }

  public func readArchiveData() throws -> Data? {
    guard isUsableFileURL(fileURL) else { throw ReturnPersistenceFailure.readFailed }
    let descriptor = open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
    if descriptor < 0 {
      if errno == ENOENT { return nil }
      throw ReturnPersistenceFailure.readFailed
    }
    defer { _ = close(descriptor) }
    guard try isRegularFile(descriptor) else { throw ReturnPersistenceFailure.readFailed }

    let allocationLimit = ArchiveCodec.maximumArchiveBytes + 1
    // One capped allocation avoids metadata races and Data's append-capacity growth.
    var data = Data(count: allocationLimit)
    let used = try data.withUnsafeMutableBytes { buffer -> Int in
      var used = 0
      while used < allocationLimit {
        let amount = min(Self.chunkSize, allocationLimit - used)
        let count = read(descriptor, buffer.baseAddress?.advanced(by: used), amount)
        if count < 0 {
          if errno == EINTR { continue }
          throw ReturnPersistenceFailure.readFailed
        }
        if count == 0 { return used }
        used += count
      }
      throw ReturnPersistenceFailure.archiveTooLarge
    }
    data.count = used
    return data
  }

  public func writeAtomically(_ data: Data) throws {
    guard data.count <= ArchiveCodec.maximumArchiveBytes else {
      throw ReturnPersistenceFailure.archiveTooLarge
    }
    do {
      try publishAtomically(to: fileURL) { descriptor in
        try data.withUnsafeBytes { buffer in
          try writeAll(buffer, to: descriptor)
        }
      }
    } catch {
      throw ReturnPersistenceFailure.writeFailed
    }
  }

  /// Recovery copies bypass JSON and the import-size cap, without changing the source.
  public func copyRawArchive(to destination: URL) throws {
    guard isUsableFileURL(fileURL), isUsableFileURL(destination) else {
      throw ReturnPersistenceFailure.invalidDestination
    }
    guard
      fileURL.standardizedFileURL.resolvingSymlinksInPath()
        != destination.standardizedFileURL.resolvingSymlinksInPath()
    else { throw ReturnPersistenceFailure.invalidDestination }
    let source = open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
    guard source >= 0 else {
      throw errno == ENOENT
        ? ReturnPersistenceFailure.sourceMissing : ReturnPersistenceFailure.readFailed
    }
    defer { _ = close(source) }
    guard try isRegularFile(source) else { throw ReturnPersistenceFailure.readFailed }
    var sourceInfo = stat()
    guard fstat(source, &sourceInfo) == 0 else { throw ReturnPersistenceFailure.readFailed }
    var destinationInfo = stat()
    if stat(destination.path, &destinationInfo) == 0,
      sourceInfo.st_dev == destinationInfo.st_dev, sourceInfo.st_ino == destinationInfo.st_ino
    {
      throw ReturnPersistenceFailure.invalidDestination
    }
    do {
      try publishAtomically(to: destination) { target in
        var buffer = [UInt8](repeating: 0, count: Self.chunkSize)
        while true {
          let count = buffer.withUnsafeMutableBytes { pointer in
            read(source, pointer.baseAddress, pointer.count)
          }
          if count < 0 {
            if errno == EINTR { continue }
            throw ReturnPersistenceFailure.rawCopyFailed
          }
          if count == 0 { return }
          try buffer.withUnsafeBytes { pointer in
            try writeAll(UnsafeRawBufferPointer(rebasing: pointer[..<count]), to: target)
          }
        }
      }
    } catch {
      throw ReturnPersistenceFailure.rawCopyFailed
    }
  }

  private func isUsableFileURL(_ url: URL) -> Bool {
    url.isFileURL && !url.path.utf8.contains(0)
  }

  private func isRegularFile(_ descriptor: Int32) throws -> Bool {
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw ReturnPersistenceFailure.readFailed }
    return info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
  }

  private func writeAll(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
    var written = 0
    while written < bytes.count {
      let count = write(descriptor, bytes.baseAddress?.advanced(by: written), bytes.count - written)
      if count < 0 {
        if errno == EINTR { continue }
        throw ReturnPersistenceFailure.writeFailed
      }
      guard count > 0 else { throw ReturnPersistenceFailure.writeFailed }
      written += count
    }
  }

  private func publishAtomically(
    to destination: URL, writing: (Int32) throws -> Void
  ) throws {
    guard isUsableFileURL(destination) else { throw ReturnPersistenceFailure.invalidDestination }
    try failureInjector(.stage)
    let directory = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var template = Array(directory.appendingPathComponent(".returnqueue-XXXXXX").path.utf8CString)
    let descriptor = template.withUnsafeMutableBufferPointer { pointer in
      mkstemp(pointer.baseAddress)
    }
    guard descriptor >= 0 else { throw ReturnPersistenceFailure.writeFailed }
    let temporaryPath = String(
      decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    var descriptorIsOpen = true
    defer {
      if descriptorIsOpen { _ = close(descriptor) }
      // After a successful rename this path is already absent; cleanup never reports failure.
      _ = unlink(temporaryPath)
    }
    try writing(descriptor)
    try failureInjector(.protection)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: temporaryPath)
    #endif
    guard fsync(descriptor) == 0 else { throw ReturnPersistenceFailure.writeFailed }
    let closeResult = close(descriptor)
    descriptorIsOpen = false
    guard closeResult == 0 else { throw ReturnPersistenceFailure.writeFailed }
    try failureInjector(.replacement)
    guard rename(temporaryPath, destination.path) == 0 else {
      throw ReturnPersistenceFailure.writeFailed
    }
    // Publication is the last fallible operation. A caller can safely publish its snapshot now.
  }
}
