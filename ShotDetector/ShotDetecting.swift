// A detector consumes frames in time order and returns the shots it confirms (spec §4).
public protocol ShotDetecting {
    mutating func process(_ frame: VideoFrame) -> [ShotEvent]
    mutating func finish() -> [ShotEvent]
}

extension ShotDetecting {
    public mutating func finish() -> [ShotEvent] { [] }
}
