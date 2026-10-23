import SwiftUI

/// Trafik levhalarını vektörel çizer; görsel dosyası gerekmez.
struct TrafficSignView: View {
    let sign: SignImage
    var size: CGFloat = 150

    private let red = Color(red: 0.84, green: 0.08, blue: 0.12)
    private let blue = Color(red: 0.0, green: 0.33, blue: 0.68)

    var body: some View {
        ZStack {
            switch sign.shape {
            case .warning:
                Triangle().fill(.white)
                Triangle().stroke(red, style: .init(lineWidth: size * 0.09, lineJoin: .round))
                glyph(.black).offset(y: size * 0.1).scaleEffect(0.8)
            case .yield:
                Triangle().rotation(.degrees(180)).fill(.white)
                Triangle().rotation(.degrees(180)).stroke(red, style: .init(lineWidth: size * 0.1, lineJoin: .round))
            case .prohibitory:
                Circle().fill(.white)
                Circle().strokeBorder(red, lineWidth: size * 0.12)
                glyph(.black)
                if sign.slash == true { slash(red) }
            case .end:
                Circle().fill(.white)
                Circle().strokeBorder(Color(white: 0.25), lineWidth: size * 0.03)
                glyph(Color(white: 0.45))
                ForEach(-2...2, id: \.self) { i in
                    Rectangle().fill(Color(white: 0.3)).frame(width: size * 0.025, height: size * 0.95)
                        .offset(x: CGFloat(i) * size * 0.05).rotationEffect(.degrees(45))
                }
                .mask(Circle())
            case .mandatory:
                Circle().fill(blue)
                Circle().strokeBorder(.white, lineWidth: size * 0.03)
                glyph(.white)
            case .info:
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).fill(blue)
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).strokeBorder(.white, lineWidth: size * 0.03).padding(size * 0.03)
                glyph(.white)
            case .stop:
                Octagon().fill(red)
                Octagon().stroke(.white, lineWidth: size * 0.03).padding(size * 0.04)
                Text(sign.text ?? "DUR")
                    .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .accessibilityElement()
        .accessibilityLabel("Trafik işaret levhası")
    }

    @ViewBuilder
    private func glyph(_ color: Color) -> some View {
        if let text = sign.text, !text.isEmpty {
            Text(text)
                .font(.system(size: size * (text.count > 2 ? 0.3 : 0.4), weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
        } else if let symbol = sign.symbol {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private func slash(_ color: Color) -> some View {
        Rectangle().fill(color).frame(width: size * 0.1, height: size * 0.86).rotationEffect(.degrees(45))
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset = r.width * 0.06
        p.move(to: .init(x: r.midX, y: r.minY + inset))
        p.addLine(to: .init(x: r.maxX - inset, y: r.maxY - inset * 1.6))
        p.addLine(to: .init(x: r.minX + inset, y: r.maxY - inset * 1.6))
        p.closeSubpath()
        return p
    }
}

private struct Octagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<8 {
            let a = (Double(i) * 45 + 22.5) * .pi / 180
            let pt = CGPoint(x: r.midX + cos(a) * r.width / 2, y: r.midY + sin(a) * r.height / 2)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

#Preview {
    LazyVGrid(columns: [.init(), .init(), .init()]) {
        TrafficSignView(sign: .init(shape: .stop, symbol: nil, text: "DUR", slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .yield, symbol: nil, text: nil, slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .prohibitory, symbol: nil, text: "50", slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .end, symbol: nil, text: "50", slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .prohibitory, symbol: "arrow.uturn.backward", text: nil, slash: true), size: 90)
        TrafficSignView(sign: .init(shape: .warning, symbol: "figure.walk", text: nil, slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .mandatory, symbol: "arrow.right", text: nil, slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .info, symbol: nil, text: "P", slash: nil), size: 90)
        TrafficSignView(sign: .init(shape: .info, symbol: "fuelpump.fill", text: nil, slash: nil), size: 90)
    }
    .padding()
}
