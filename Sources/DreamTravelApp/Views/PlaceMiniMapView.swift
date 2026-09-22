import MapKit
import SwiftUI

struct PlaceMiniMapView: View {
    let place: String
    let address: String

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var state: SearchState = .loading

    private var query: String { "\(place) \(address)" }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                if let coordinate {
                    Marker(place, coordinate: coordinate)
                        .tint(DreamStyle.accent)
                }
            }

            if state != .ready {
                Rectangle()
                    .fill(.regularMaterial)

                VStack(spacing: 7) {
                    if state == .loading {
                        ProgressView()
                        Text("正在定位地址")
                    } else {
                        Image(systemName: "map")
                        Text("暂时无法载入地图预览")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        }
        .task(id: query) {
            await locatePlace()
        }
    }

    @MainActor
    private func locatePlace() async {
        state = .loading
        coordinate = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let foundCoordinate = response.mapItems.first?.placemark.coordinate else {
                state = .failed
                return
            }

            coordinate = foundCoordinate
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: foundCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
            state = .ready
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    private enum SearchState {
        case loading
        case ready
        case failed
    }
}
