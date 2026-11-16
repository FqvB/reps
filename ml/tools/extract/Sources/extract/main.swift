// main.swift — extract 13 body keypoints per frame from a video, using Apple Vision.
//
// Usage:
//     extract <input video> <output json>
//
// Output (the schema the training scripts and the iOS app both rely on):
// {
//   "video": "<file stem>",
//   "fps": 60,
//   "width": 1080, "height": 1920,          // as displayed, i.e. after rotation
//   "joints": ["nose", "l_shoulder", ... 13 names ...],
//   "frames": [ [[x, y, confidence] x 13], ... one entry per video frame ... ]
// }
// x and y are fractions of the displayed width and height, origin TOP-LEFT.
// A frame where no person is found is 13 x [null, null, 0].
// The number of entries in "frames" equals the number of frames in the video,
// so the label CSVs line up by index.

import AVFoundation
import Foundation
import Vision

// MARK: - Joint order (never change this; the iOS app uses the same list)

let jointNames: [String] = [
    "nose",
    "l_shoulder", "r_shoulder",
    "l_elbow", "r_elbow",
    "l_wrist", "r_wrist",
    "l_hip", "r_hip",
    "l_knee", "r_knee",
    "l_ankle", "r_ankle",
]

let visionJointNames: [VNHumanBodyPoseObservation.JointName] = [
    .nose,
    .leftShoulder, .rightShoulder,
    .leftElbow, .rightElbow,
    .leftWrist, .rightWrist,
    .leftHip, .rightHip,
    .leftKnee, .rightKnee,
    .leftAnkle, .rightAnkle,
]

// MARK: - Output structure

struct KeypointFile: Encodable {
    let video: String
    let fps: Double
    let width: Int
    let height: Int
    let joints: [String]
    // Each frame: 13 joints, each [x, y, confidence]; x and y are nil when the joint is missing.
    let frames: [[[Double?]]]
}

let emptyFrame: [[Double?]] = Array(repeating: [nil, nil, 0.0], count: jointNames.count)

// MARK: - Arguments

let commandLineArguments = CommandLine.arguments
guard commandLineArguments.count == 3 else {
    print("usage: extract <input video> <output json>")
    exit(1)
}
let inputURL = URL(fileURLWithPath: commandLineArguments[1])
let outputURL = URL(fileURLWithPath: commandLineArguments[2])

// MARK: - Open the video

let asset = AVURLAsset(url: inputURL)
guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
    print("no video track in \(inputURL.path)")
    exit(1)
}

let nominalFrameRate = try await Double(videoTrack.load(.nominalFrameRate))
let naturalSize = try await videoTrack.load(.naturalSize)
let preferredTransform = try await videoTrack.load(.preferredTransform)

// iPhone portrait videos are stored sideways with a rotation flag. Vision needs to know
// the real orientation, and the JSON should describe the picture as you see it.
func orientation(from transform: CGAffineTransform) -> (CGImagePropertyOrientation, isRotated: Bool) {
    let angleInDegrees = atan2(transform.b, transform.a) * 180 / .pi
    switch Int(angleInDegrees.rounded()) {
    case 90:   return (.right, true)    // portrait, home button at the bottom
    case -90:  return (.left, true)     // portrait, upside down
    case 180, -180: return (.down, false)
    default:   return (.up, false)
    }
}

let (imageOrientation, isRotated) = orientation(from: preferredTransform)
let displayedWidth = Int(isRotated ? naturalSize.height : naturalSize.width)
let displayedHeight = Int(isRotated ? naturalSize.width : naturalSize.height)

let reader = try AVAssetReader(asset: asset)
let readerOutput = AVAssetReaderTrackOutput(
    track: videoTrack,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
readerOutput.alwaysCopiesSampleData = false
reader.add(readerOutput)
reader.startReading()

// MARK: - Choosing the golfer when more than one person is in frame

// The golfer is the closest person to the camera, so pick the observation with the
// longest shoulder-to-hip distance. Neighbours in the next bay come out smaller.
func torsoLength(of observation: VNHumanBodyPoseObservation) -> Double {
    guard
        let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
        let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
        let leftHip = try? observation.recognizedPoint(.leftHip),
        let rightHip = try? observation.recognizedPoint(.rightHip),
        leftShoulder.confidence > 0.2, rightShoulder.confidence > 0.2,
        leftHip.confidence > 0.2, rightHip.confidence > 0.2
    else { return 0 }
    let shoulderMidX = (leftShoulder.location.x + rightShoulder.location.x) / 2
    let shoulderMidY = (leftShoulder.location.y + rightShoulder.location.y) / 2
    let hipMidX = (leftHip.location.x + rightHip.location.x) / 2
    let hipMidY = (leftHip.location.y + rightHip.location.y) / 2
    return hypot(shoulderMidX - hipMidX, shoulderMidY - hipMidY)
}

// MARK: - Frame loop

var frames: [[[Double?]]] = []
frames.reserveCapacity(Int(nominalFrameRate * 60 * 15)) // room for a 15-minute video
let poseRequest = VNDetectHumanBodyPoseRequest()
let startTime = Date()

while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
    defer { CMSampleBufferInvalidate(sampleBuffer) }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        frames.append(emptyFrame)
        continue
    }

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
    try handler.perform([poseRequest])

    guard
        let observations = poseRequest.results, !observations.isEmpty,
        let golfer = observations.max(by: { torsoLength(of: $0) < torsoLength(of: $1) })
    else {
        frames.append(emptyFrame)
        continue
    }

    var frame: [[Double?]] = []
    frame.reserveCapacity(jointNames.count)
    for visionJoint in visionJointNames {
        if let point = try? golfer.recognizedPoint(visionJoint), point.confidence > 0 {
            // Vision's origin is bottom-left; flip y so the JSON is top-left like image pixels.
            frame.append([Double(point.location.x), Double(1 - point.location.y), Double(point.confidence)])
        } else {
            frame.append([nil, nil, 0.0])
        }
    }
    frames.append(frame)

    if frames.count % 600 == 0 {
        let elapsed = Date().timeIntervalSince(startTime)
        let framesPerSecond = Double(frames.count) / elapsed
        print("\(frames.count) frames  (\(Int(framesPerSecond)) fps)")
    }
}

if reader.status == .failed {
    print("reading failed: \(reader.error?.localizedDescription ?? "unknown")")
    exit(1)
}

// MARK: - Write

let keypointFile = KeypointFile(
    video: inputURL.deletingPathExtension().lastPathComponent,
    fps: nominalFrameRate,
    width: displayedWidth,
    height: displayedHeight,
    joints: jointNames,
    frames: frames
)

let encoder = JSONEncoder()
let data = try encoder.encode(keypointFile)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outputURL)

let framesWithPerson = frames.filter { $0[0][2] != 0 || $0[1][2] != 0 }.count
print("wrote \(outputURL.lastPathComponent): \(frames.count) frames, person found in \(framesWithPerson), \(Int(Date().timeIntervalSince(startTime))) s")