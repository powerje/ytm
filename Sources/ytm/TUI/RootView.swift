import Combine
import Foundation
import SwiftTUI

/// Holds the rendered lines for the view. Updated on the main actor; read by
/// the view on the main thread.
final class ScreenStore: ObservableObject, @unchecked Sendable {
    let objectWillChange = ObservableObjectPublisher()
    private(set) var lines: [StyledLine] = []

    @MainActor
    func set(_ lines: [StyledLine]) {
        guard lines != self.lines else { return }
        objectWillChange.send()
        self.lines = lines
    }
}

struct RootView: View {
    @ObservedObject var store: ScreenStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.lines) { line in
                Text(line.attributedString)
            }
        }
    }
}

extension StyledLine {
    var attributedString: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.style.tint {
            case .normal: break
            case .dim: part[AttributeScopes.SwiftTUIAttributes.ForegroundColorAttribute.self] = .brightBlack
            case .accent: part[AttributeScopes.SwiftTUIAttributes.ForegroundColorAttribute.self] = .cyan
            case .playing: part[AttributeScopes.SwiftTUIAttributes.ForegroundColorAttribute.self] = .green
            case .warning: part[AttributeScopes.SwiftTUIAttributes.ForegroundColorAttribute.self] = .yellow
            }
            if segment.style.bold { part[AttributeScopes.SwiftTUIAttributes.BoldAttribute.self] = true }
            if segment.style.inverted { part[AttributeScopes.SwiftTUIAttributes.InvertedAttribute.self] = true }
            result += part
        }
        return result
    }
}
