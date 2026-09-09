import SwiftUI

@main
struct DamaApp: App {
    @NSApplicationDelegateAdaptor(DamaAppDelegate.self) private var delegate
    @StateObject private var workspace = ReviewWorkspace.shared
    var body: some Scene {
        Window("다마", id: "review") {
            ReviewShell(workspace: workspace)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("검수") {
                Button("검수 실행 취소", action: workspace.undo)
                    .disabled(!workspace.canEdit || workspace.state?.canUndo != true)
                    .keyboardShortcut("z", modifiers: [.command, .option])
                Button("검수 다시 실행", action: workspace.redo)
                    .disabled(!workspace.canEdit || workspace.state?.canRedo != true)
                    .keyboardShortcut("z", modifiers: [.command, .option, .shift])
                Divider()
                Button("JSON 내보내기") { workspace.export(.json) }.disabled(!workspace.canExport)
                Button("TXT 내보내기") { workspace.export(.text) }.disabled(!workspace.canExport)
                #if DEBUG
                Divider()
                Button("합성 테스트 데이터 열기", action: workspace.importFixture)
                    .disabled(!workspace.didLoad || !workspace.canLeave)
                #endif
            }
        }
        Settings {
            VStack(alignment: .leading, spacing: 16) {
                Text("다마 설정").font(.title2)
                Text("마이크 녹음·파일 반입·원본 보존")
                Text("수정본은 이 Mac에 저장됩니다. JSON과 TXT는 내보내기에서 저장 위치를 선택합니다.")
                Text("메뉴바 좌클릭은 녹음 시작·종료, 우클릭은 패널 열기입니다. 클라우드 전송은 녹음별로 확인합니다.")
                    .foregroundStyle(.secondary)
                APIKeySettings()
                Text("macOS 26.6.2 이상 · Apple Silicon").font(.caption)
            }.padding(24).frame(width: 400)
        }
    }
}
