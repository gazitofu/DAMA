import Foundation
import AVFoundation
import Combine
import DamaCore

@MainActor public final class SegmentPlayback: ObservableObject {
    @Published public private(set) var playingID: String?
    @Published public private(set) var positionUs: Int64 = 0
    @Published public var message: String?
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    public init() {}
    public static func range(startUs: Int64?, endUs: Int64?, duration: Double) throws -> ClosedRange<Double> {
        guard let startUs, let endUs, startUs >= 0, endUs > startUs, duration.isFinite,
              Double(startUs) / 1_000_000 < duration else { throw LibraryFailure.invalidInput }
        return (Double(startUs) / 1_000_000)...min(Double(endUs) / 1_000_000, duration)
    }
    public func play(url: URL, id: String, startUs: Int64?, endUs: Int64?) {
        if playingID == id { stop(); return }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let range = try Self.range(startUs: startUs, endUs: endUs, duration: player.duration)
            player.currentTime = range.lowerBound
            guard player.prepareToPlay(), player.play() else { throw LibraryFailure.missingFile }
            self.player = player; playingID = id; message = nil
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let player = self.player else { return }
                    self.positionUs = Int64(player.currentTime * 1_000_000)
                    if !player.isPlaying || player.currentTime >= range.upperBound { self.stop(); return }
                    try? await Task.sleep(for: .milliseconds(30))
                }
            }
        } catch { message = "이 구간을 재생하지 못했습니다. 원음 접근 권한과 타임스탬프를 확인해 주세요." }
    }
    public func stop() { ticker?.cancel(); ticker = nil; player?.stop(); player = nil; playingID = nil }
}
