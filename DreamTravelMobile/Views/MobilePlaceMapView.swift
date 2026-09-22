import MapKit
import SwiftUI

struct MobilePlaceMapView: View {
    @Environment(\.planAtmosphere) private var atmosphere
    let stop: MobileStop
    @Binding var coordinate: CLLocationCoordinate2D?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoading = true
    @State private var didFail = false

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                if let coordinate {
                    Marker(stop.place, coordinate: coordinate)
                        .tint(atmosphere.accent)
                }
            }

            if isLoading || didFail {
                Rectangle().fill(.regularMaterial)
                if isLoading {
                    ProgressView("正在定位")
                        .font(.caption)
                } else {
                    ContentUnavailableView("地图暂时不可用", systemImage: "map", description: Text("仍可用下方按钮打开地图 App"))
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: stop.searchText) {
            await locate()
        }
    }

    @MainActor
    private func locate() async {
        isLoading = true
        didFail = false
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            isLoading = false
            didFail = coordinate == nil
        }
        defer { timeoutTask.cancel() }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = stop.searchText

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let found = response.mapItems.first?.placemark.coordinate else {
                isLoading = false
                didFail = true
                return
            }
            coordinate = found
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: found,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
            isLoading = false
            didFail = false
        } catch {
            isLoading = false
            didFail = true
        }
    }
}
