import SwiftUI

// MARK: - Renkler

enum Palette {
    static let tint = Color(red: 0, green: 0.384, blue: 0.8)          // #0062CC
    static let indigo = Color(red: 0.369, green: 0.361, blue: 0.902)  // #5E5CE6
    static let red = Color(red: 0.843, green: 0, blue: 0.082)         // #D70015
    static let green = Color(red: 0.141, green: 0.541, blue: 0.239)   // #248A3D
    static let orange = Color(red: 0.788, green: 0.204, blue: 0)      // #C93400
    static let ink = Color(red: 0.043, green: 0.102, blue: 0.173)     // #0B1A2C
    static let gold = Color(red: 0.949, green: 0.718, blue: 0.02)     // #F2B705
}

// MARK: - Liquid Glass
// iOS 26 SDK ile derlendiğinde gerçek `glassEffect` kullanılır;
// daha eski SDK / iOS sürümlerinde materyal + parlak kenar ile taklit edilir.

struct GlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var interactive = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
    #endif

    private func fallback(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                    shape.fill(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

extension View {
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    func glassCapsule(tint: Color? = nil) -> some View {
        glass(Capsule(), tint: tint, interactive: true)
    }
}

// MARK: - Ortak bileşenler

/// Yuvarlak cam buton (geri, bildirim, profil...)
struct GlassIconButton: View {
    let systemName: String
    var label: String
    var size: CGFloat = 46
    var foreground: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

/// Dolu, renkli hap buton
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Palette.tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(PressableStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Inset-grouped tarzı beyaz kart
struct Card<Content: View>: View {
    var padding: EdgeInsets = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            if let trailing {
                Button(trailing) { trailingAction?() }
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Renkli ikon karesi (Ayarlar uygulaması stili)
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct RowDivider: View {
    var leading: CGFloat = 60
    var body: some View {
        Divider().padding(.leading, leading)
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Palette.tint

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill))
                Capsule().fill(tint).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 5)
    }
}

/// Üstte kayan cam başlık çubuğu için ortak düzen
struct GlassTopBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
    }
}

/// Alt sekme çubuğu yüksekliği kadar boşluk
struct TabBarSpacer: View {
    var body: some View { Color.clear.frame(height: 110) }
}
