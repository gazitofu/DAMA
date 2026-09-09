import DamaCore
import SwiftUI

struct ReviewShell: View {
    private static let contractType = TranscriptDocument.self

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("담아")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("검수할 세션이 없습니다.")
                .font(.title3)

            Text("녹음과 전사는 아직 지원하지 않습니다.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
        .frame(minWidth: 900, minHeight: 600)
        .accessibilityElement(children: .contain)
        .onAppear {
            _ = Self.contractType
        }
    }
}
