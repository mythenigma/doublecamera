import AVFoundation
import CoreImage
import CoreMedia
import Foundation

/// Writes synchronized dual-camera sample buffers to disk.
///
/// - `.split` / `.pip` compose both feeds into a single `.mov` (Core Image).
///   With `dualOrientation` they compose into *two* files — one portrait, one landscape.
/// - `.dualFile` writes each feed to its own independent `.mov`.
///
/// All `append` / `start` / `stop` calls are expected to arrive on a single
/// serial queue (the capture data queue) so internal state needs no extra locking.
final class DualStreamRecorder {
    struct Output {
        let mode: CaptureMode
        let urls: [URL]
    }

    private(set) var isRecording = false

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// One composed output file (canvas + writer). Two of these exist when
    /// `dualOrientation` is on (portrait + landscape).
    private final class CompositeTarget {
        let writer: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let size: CGSize
        let portrait: Bool

        init(writer: AVAssetWriter, videoInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, size: CGSize, portrait: Bool) {
            self.writer = writer
            self.videoInput = videoInput
            self.adaptor = adaptor
            self.size = size
            self.portrait = portrait
        }
    }

    private var compositeTargets: [CompositeTarget] = []

    // Dual-file path
    private var backWriter: AVAssetWriter?
    private var backVideoInput: AVAssetWriterInput?
    private var frontWriter: AVAssetWriter?
    private var frontVideoInput: AVAssetWriterInput?

    // Shared audio (attached to the primary file in every mode)
    private var audioInput: AVAssetWriterInput?

    private var mode: CaptureMode = .pip
    private var urls: [URL] = []
    private var sessionStarted = false
    private var dualFileSize = CGSize(width: 1080, height: 1920)

    /// Latest front frame, retained so it can be paired with the next back frame
    /// even when the synchronizer drops one side.
    private var latestFront: CVPixelBuffer?

    // MARK: - Lifecycle

    func start(mode: CaptureMode, portrait: Bool, quality: VideoQuality, dualOrientation: Bool) throws -> [URL] {
        self.mode = mode
        sessionStarted = false
        latestFront = nil
        compositeTargets = []

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = Self.timestamp()

        switch mode {
        case .split, .pip:
            // Primary orientation matches how the phone is held; the optional
            // second target is the opposite orientation.
            var orientations: [Bool] = [portrait]
            if dualOrientation { orientations.append(!portrait) }

            var made: [URL] = []
            for isPortrait in orientations {
                let suffix = dualOrientation ? (isPortrait ? "-portrait" : "-landscape") : ""
                let url = directory.appendingPathComponent("DualCamera-\(stamp)\(suffix).mov")
                try addCompositeTarget(url: url, size: quality.renderSize(portrait: isPortrait), portrait: isPortrait)
                made.append(url)
            }
            urls = made

        case .dualFile:
            dualFileSize = quality.renderSize(portrait: portrait)
            let backURL = directory.appendingPathComponent("DualCamera-\(stamp)-back.mov")
            let frontURL = directory.appendingPathComponent("DualCamera-\(stamp)-front.mov")
            try setupDualFile(backURL: backURL, frontURL: frontURL)
            urls = [backURL, frontURL]
        }

        isRecording = true
        return urls
    }

    func stop(completion: @escaping (Output) -> Void) {
        guard isRecording else {
            completion(Output(mode: mode, urls: []))
            return
        }
        isRecording = false

        let finishedMode = mode
        let finishedURLs = urls
        let group = DispatchGroup()

        let writers = compositeTargets.map(\.writer) + [backWriter, frontWriter].compactMap { $0 }
        for writer in writers where writer.status == .writing {
            group.enter()
            writer.finishWriting { group.leave() }
        }

        group.notify(queue: .main) {
            completion(Output(mode: finishedMode, urls: finishedURLs))
        }

        resetInputs()
    }

    // MARK: - Frame ingest

    func append(back: CMSampleBuffer?, front: CMSampleBuffer?, audio: CMSampleBuffer?) {
        guard isRecording else { return }

        if let front, let pixelBuffer = CMSampleBufferGetImageBuffer(front) {
            latestFront = pixelBuffer
        }

        switch mode {
        case .split, .pip:
            appendComposite(back: back, audio: audio)
        case .dualFile:
            appendDualFile(back: back, front: front, audio: audio)
        }
    }

    // MARK: - Composite (split / pip)

    private func addCompositeTarget(url: URL, size: CGSize, portrait: Bool) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height
            ]
        )

        if writer.canAdd(videoInput) { writer.add(videoInput) }

        // Audio rides on the first composite target only.
        if compositeTargets.isEmpty {
            let audio = makeAudioInput()
            if writer.canAdd(audio) { writer.add(audio) }
            audioInput = audio
        }

        compositeTargets.append(
            CompositeTarget(writer: writer, videoInput: videoInput, adaptor: adaptor, size: size, portrait: portrait)
        )
    }

    private func appendComposite(back: CMSampleBuffer?, audio: CMSampleBuffer?) {
        if let back, let backPixels = CMSampleBufferGetImageBuffer(back) {
            let time = CMSampleBufferGetPresentationTimeStamp(back)

            for target in compositeTargets {
                startSessionIfNeeded(writer: target.writer, at: time)
                guard target.writer.status == .writing,
                      target.videoInput.isReadyForMoreMediaData,
                      let pool = target.adaptor.pixelBufferPool else { continue }

                var rendered: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &rendered)
                guard let output = rendered else { continue }

                composite(back: backPixels, front: latestFront, size: target.size, portrait: target.portrait, into: output)
                target.adaptor.append(output, withPresentationTime: time)
            }
        }

        appendAudio(audio)
    }

    /// Draws the back feed (and optionally the front feed) into `output`
    /// according to the current mode and target orientation.
    private func composite(back: CVPixelBuffer, front: CVPixelBuffer?, size: CGSize, portrait: Bool, into output: CVPixelBuffer) {
        let result = DualFrameCompositor.compose(back: back, front: front, mode: mode, size: size, portrait: portrait)
        ciContext.render(result, to: output)
    }

    // MARK: - Dual file

    private func setupDualFile(backURL: URL, frontURL: URL) throws {
        let bWriter = try AVAssetWriter(outputURL: backURL, fileType: .mov)
        let bInput = makeVideoInput()
        let audio = makeAudioInput()
        if bWriter.canAdd(bInput) { bWriter.add(bInput) }
        if bWriter.canAdd(audio) { bWriter.add(audio) }

        let fWriter = try AVAssetWriter(outputURL: frontURL, fileType: .mov)
        let fInput = makeVideoInput()
        if fWriter.canAdd(fInput) { fWriter.add(fInput) }

        backWriter = bWriter
        backVideoInput = bInput
        frontWriter = fWriter
        frontVideoInput = fInput
        audioInput = audio
    }

    private func appendDualFile(back: CMSampleBuffer?, front: CMSampleBuffer?, audio: CMSampleBuffer?) {
        if let back {
            let time = CMSampleBufferGetPresentationTimeStamp(back)
            startSessionIfNeeded(writer: backWriter, at: time)
            startSessionIfNeeded(writer: frontWriter, at: time)
        }

        if let back, let writer = backWriter, writer.status == .writing,
           let input = backVideoInput, input.isReadyForMoreMediaData {
            input.append(back)
        }

        if let front, let writer = frontWriter, writer.status == .writing,
           let input = frontVideoInput, input.isReadyForMoreMediaData {
            input.append(front)
        }

        appendAudio(audio)
    }

    // MARK: - Shared helpers

    private func appendAudio(_ audio: CMSampleBuffer?) {
        guard let audio, let input = audioInput, input.isReadyForMoreMediaData,
              let writer = primaryWriter, writer.status == .writing, sessionStarted else { return }
        input.append(audio)
    }

    private var primaryWriter: AVAssetWriter? {
        mode.producesComposite ? compositeTargets.first?.writer : backWriter
    }

    private func startSessionIfNeeded(writer: AVAssetWriter?, at time: CMTime) {
        guard let writer else { return }
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: time)
        }
        sessionStarted = true
    }

    private func makeVideoInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dualFileSize.width,
            AVVideoHeightKey: dualFileSize.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func makeAudioInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 64_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func resetInputs() {
        compositeTargets = []
        backWriter = nil
        backVideoInput = nil
        frontWriter = nil
        frontVideoInput = nil
        audioInput = nil
        latestFront = nil
        sessionStarted = false
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
