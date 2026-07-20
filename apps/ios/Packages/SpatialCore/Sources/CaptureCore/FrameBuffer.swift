import Foundation
import SpatialProtocol

public struct CapturedFrame: Sendable, Identifiable {
  public let id: String
  public let timestamp: TimeInterval
  public let imageData: Data

  public init(id: String, timestamp: TimeInterval, imageData: Data) {
    self.id = id
    self.timestamp = timestamp
    self.imageData = imageData
  }
}

public actor FrameBuffer {
  public let capacity: Int
  private var frames: [CapturedFrame] = []

  public init(capacity: Int = 3) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  public func insert(_ frame: CapturedFrame) {
    frames.append(frame)
    if frames.count > capacity {
      frames.removeFirst(frames.count - capacity)
    }
  }

  public func latest() -> CapturedFrame? {
    frames.last
  }
}
