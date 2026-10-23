import SwiftUI
import MapKit

struct RoutesMapView: View {
    @Environment(AppState.self) private var state
    @Environment(AuthStore.self) private var auth

    @State private var cities: [City] = []
    @State private var routes: [DrivingRoute] = []
    @State private var city = "İstanbul"
    @State private var selectedID: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var sheetExpanded = true
    @AppStorage("savedRoutes") private var savedRaw = ""

    private var route: DrivingRoute? { routes.first { $0.id == selectedID } ?? routes.first }
    private var coords: [CLLocationCoordinate2D] { route?.path.map { .init(latitude: $0[0], longitude: $0[1]) } ?? [] }
    private var saved: Set<String> { Set(savedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        Map(position: $camera) {
            if let route, !route.locked, let first = coords.first, let last = coords.last {
                MapPolyline(coordinates: coords)
                    .stroke(Palette.tint, style: .init(lineWidth: 7, lineCap: .round, lineJoin: .round))
                Annotation("Başlangıç", coordinate: first) { dot(Palette.green) }
                Annotation("Bitiş", coordinate: last) { dot(Palette.red) }
                ForEach(Array(route.checkpoints.enumerated()), id: \.offset) { i, c in
                    Annotation(c.title, coordinate: .init(latitude: c.lat, longitude: c.lng)) {
                        Text("\(i + 1)")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.tint)
                            .frame(width: 30, height: 30)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(Palette.tint, lineWidth: 3))
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .blur(radius: route?.locked == true ? 6 : 0)
        .ignoresSafeArea()
        .overlay(alignment: .top) { filters }
        .overlay(alignment: .topTrailing) { mapControls }
        .safeAreaInset(edge: .bottom) { detailSheet }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let res: [String: [City]]? = try? await APIClient.shared.get("/v1/routes/cities")
            cities = res?["cities"] ?? []
        }
        // Şehir değişince ya da premium açılınca güzergahları yeniden yükle
        .task(id: "\(city)|\(auth.entitlements.scopes.sorted())") { await loadRoutes() }
    }

    private func loadRoutes() async {
        let res: [String: [DrivingRoute]]? = try? await APIClient.shared.get("/v1/routes", query: ["city": city])
        routes = res?["routes"] ?? []
        if route == nil || !routes.contains(where: { $0.id == selectedID }) { selectedID = routes.first?.id }
        focus()
    }

    private func focus() {
        guard let route else { return }
        let points = coords.isEmpty ? (route.center.map { [CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])] } ?? []) : coords
        guard let c = points.first else { return }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2 - 0.004, longitude: (lngs.min()! + lngs.max()!) / 2)
        withAnimation {
            camera = .region(.init(center: points.count > 1 ? center : c,
                                   span: .init(latitudeDelta: max(0.025, (lats.max()! - lats.min()!) * 2.6),
                                               longitudeDelta: max(0.025, (lngs.max()! - lngs.min()!) * 2.6))))
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 4))
    }

    private var filters: some View {
        HStack(spacing: 10) {
            menu(label: "İl", value: city) {
                ForEach(cities, id: \.name) { c in
                    Button(c.name) { city = c.name }
                }
            }
            menu(label: "İlçe", value: route?.district ?? "–") {
                ForEach(routes) { r in
                    Button { selectedID = r.id; focus() } label: {
                        Label(r.district, systemImage: r.locked ? "lock.fill" : "mappin")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func menu<C: View>(label: String, value: String, @ViewBuilder content: () -> C) -> some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).frame(height: 48)
            .contentShape(Capsule())
        }
        .glass(Capsule(), interactive: true)
    }

    private var mapControls: some View {
        VStack(spacing: 0) {
            Button {} label: { Image(systemName: "map").frame(width: 48, height: 48) }
                .accessibilityLabel("Harita katmanları")
            Divider().frame(width: 30)
            Button { focus() } label: { Image(systemName: "location.fill").foregroundStyle(Palette.tint).frame(width: 48, height: 48) }
                .accessibilityLabel("Güzergaha odaklan")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.primary)
        .glass(Capsule())
        .padding(.trailing, 16)
        .padding(.top, 66)
    }

    @ViewBuilder
    private var detailSheet: some View {
        if let route {
            VStack(spacing: 14) {
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .onTapGesture { withAnimation(.spring) { sheetExpanded.toggle() } }
                    .accessibilityLabel(sheetExpanded ? "Daralt" : "Genişlet")

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.name).font(.system(size: 22, weight: .bold))
                        Text("Direksiyon sınav güzergahı · \(route.distanceKm.formatted(.number.precision(.fractionLength(1)))) km")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { toggleSaved(route.id) } label: {
                        Image(systemName: saved.contains(route.id) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Güzergahı kaydet")
                }

                if route.locked {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill").font(.system(size: 24)).foregroundStyle(Palette.tint)
                        Text("\(route.checkpointCount) kontrol noktası Premium'a özel").font(.system(size: 17, weight: .semibold))
                        PrimaryButton(title: "Kilidi Aç", systemImage: "star.fill") { state.showPaywall = true }
                    }
                    .padding(.vertical, 8)
                } else if sheetExpanded {
                    VStack(spacing: 0) {
                        ForEach(Array(route.checkpoints.enumerated()), id: \.offset) { i, c in
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 28, height: 28).background(Palette.tint, in: Circle())
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(c.title).font(.system(size: 16, weight: .semibold))
                                    Text(c.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 52)
                            if i < route.checkpoints.count - 1 { Divider().padding(.leading, 40) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    HStack(spacing: 10) {
                        SecondaryButton(title: "Videoyu İzle") { state.selectedTab = .lessons }
                        PrimaryButton(title: "Yol Tarifi") {
                            guard let start = coords.first else { return }
                            let item = MKMapItem(placemark: .init(coordinate: start))
                            item.name = route.name
                            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .glass(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 84)
            .animation(.spring(duration: 0.35), value: sheetExpanded)
        } else {
            ProgressView()
                .padding(24)
                .glass(Circle())
                .padding(.bottom, 100)
        }
    }

    private func toggleSaved(_ id: String) {
        var s = saved
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        savedRaw = s.sorted().joined(separator: ",")
    }
}
