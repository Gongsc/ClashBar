import SwiftUI

enum AppSurfaceFallbackStyle {
    case material(Material)
    case color(Color)
}

struct AppMaterialSurface: View {
    let cornerRadius: CGFloat
    let fallbackStyle: AppSurfaceFallbackStyle
    let stroke: Color
    var lineWidth: CGFloat = MenuBarLayoutTokens.stroke

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)

        Group {
            switch self.fallbackStyle {
            case let .material(material):
                shape.fill(material)
            case let .color(color):
                shape.fill(color)
            }
        }
        .overlay {
            shape.stroke(self.stroke, lineWidth: self.lineWidth)
        }
    }
}

extension View {
    @ViewBuilder
    func appBorderedButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

protocol TranslatingView: View {
    var appViewModel: AppViewModel { get }
}

extension TranslatingView {
    var language: AppLanguage {
        appViewModel.uiLanguage
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: self.language, args: args)
    }
}
