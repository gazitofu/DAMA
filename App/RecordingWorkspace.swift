import AppKit
import DamaAudio
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RecordingWorkspace: ObservableObject {
    static let shared = RecordingWorkspace()
    let capture = MicrophoneCapture()
    @Published private(set) var records: [AudioManifest] = []
    @Published private(set) var working = false
    @Published private(set) var ready = false
    @Published var message: String?
    private var library: AudioLibrary?
    private var root: URL?

    func start() {
        guard library == nil else { return }
        do {
            let root = try AudioFiles.root()
            self.root = root
            let library = AudioLibrary(root: root)
            self.library = library
            capture.onSaved = { [weak self] saved in self?.refreshAndPrepare(saved.id) }
            Task {
                defer { ready = true }
                do { records = try await library.list(recover: true) }
                catch { message = "저장된 녹음 목록을 열지 못했습니다. 원본 폴더는 보존되어 있습니다." }
            }
        } catch { message = "저장소를 열지 못했습니다. 저장 공간과 접근 권한을 확인해 주세요." }
    }

    func toggleRecord() {
        guard ready, !capture.needsFinalization else { return }
        if !capture.phase.busy && !UserDefaults.standard.bool(forKey: "microphoneIntroductionSeen") {
            let alert = NSAlert()
            alert.messageText = "마이크로 대화를 녹음하고 원본을 이 Mac에 저장합니다."
            alert.informativeText = "메뉴바 좌클릭은 녹음 시작·종료, 우클릭은 패널 열기입니다. 참석자에게 녹음 사실을 알리고 조직의 보안 정책을 확인해 주세요. API 키 없이 녹음할 수 있습니다."
            alert.addButton(withTitle: "마이크 접근 허용")
            alert.addButton(withTitle: "나중에 설정")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(true, forKey: "microphoneIntroductionSeen")
        }
        capture.toggle()
    }

    func importFile() {
        guard !working, !capture.phase.busy, let library else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "M4A/WAV 원본을 이 Mac의 다마 저장소로 복사합니다."
        working = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url = panel.url else { self.working = false; return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() }; self.working = false }
                do {
                    let record = try await library.importFile(url)
                    self.records = try await library.list()
                    await self.prepare(record.id, library: library)
                } catch {
                    self.message = "파일을 가져오지 못했습니다. 원본 파일과 저장 공간을 확인해 주세요."
                    self.records = (try? await library.list()) ?? self.records
                }
            }
        }
    }

    private func refreshAndPrepare(_ id: String) {
        guard let library else { return }
        Task {
            records = (try? await library.list()) ?? records
            await prepare(id, library: library)
        }
    }

    private func prepare(_ id: String, library: AudioLibrary) async {
        do { _ = try await library.prepareAnalysis(id) }
        catch {
            if error as? AudioFailure == .phaseCancellation || error as? AudioFailure == .channelConfirmationRequired {
                message = "원본은 저장했습니다. 채널을 자동으로 합칠 수 없어 분석 준비를 멈췄습니다. 채널 구성을 확인해 주세요."
            } else { message = "분석 파일을 준비하지 못했습니다. 저장된 원본은 유지됩니다." }
        }
        records = (try? await library.list()) ?? records
    }

    func retryAnalysis(_ id: String) {
        guard !working, !capture.phase.busy, let library else { return }
        working = true
        Task { await prepare(id, library: library); working = false }
    }

    func reveal(_ record: AudioManifest) {
        guard let root, let session = try? AudioFiles.session(record.id, root: root) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([session.appendingPathComponent("audio/source")])
    }
}
