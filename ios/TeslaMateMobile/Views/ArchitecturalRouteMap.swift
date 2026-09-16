import MapLibre
import SwiftUI

/// The atlas uses WGS84 coordinates directly, matching the TeslaMate track.
struct ArchitecturalRouteMap: UIViewRepresentable {
    let points: [TrackPoint]
    let fitRequest: Int
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: Bundle.main.url(forResource: "ArchitecturalMap", withExtension: "json"))
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .light
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.logoView.isHidden = true
        // Keep the SDK attribution button, plus the visible provider credit in SwiftUI.
        map.accessibilityLabel = "建筑区位行程地图"
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFit != fitRequest {
            context.coordinator.lastFit = fitRequest
            context.coordinator.fit(map)
        }
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: ArchitecturalRouteMap
        var lastFit = -1
        init(_ parent: ArchitecturalRouteMap) { self.parent = parent }

        var coordinates: [CLLocationCoordinate2D] {
            parent.points.filter(\.hasValidCoordinate).compactMap {
                guard let lat = $0.latitude, let lon = $0.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }

        func fit(_ map: MLNMapView) {
            let coords = coordinates
            guard let first = coords.first else { return }
            if coords.count == 1 {
                map.setCenter(first, zoomLevel: 14, animated: false)
            } else {
                map.setVisibleCoordinates(coords, count: UInt(coords.count),
                                          edgePadding: UIEdgeInsets(top: 56, left: 44, bottom: 54, right: 44), animated: false)
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let coords = coordinates
            guard let first = coords.first, let last = coords.last else { return }
            if coords.count > 1 {
                let line = MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
                let source = MLNShapeSource(identifier: "trip", shape: line, options: nil)
                style.addSource(source)
                let casing = MLNLineStyleLayer(identifier: "trip-casing", source: source)
                casing.lineColor = NSExpression(forConstantValue: UIColor.white)
                casing.lineWidth = NSExpression(forConstantValue: 7)
                casing.lineJoin = NSExpression(forConstantValue: "round")
                casing.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(casing)
                let route = MLNLineStyleLayer(identifier: "trip-line", source: source)
                route.lineColor = NSExpression(forConstantValue: UIColor(red: 0.12, green: 0.46, blue: 0.49, alpha: 1))
                route.lineWidth = NSExpression(forConstantValue: 3.5)
                route.lineJoin = NSExpression(forConstantValue: "round")
                route.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(route)
            }
            for (index, coord) in [first, last].enumerated() {
                if index == 1 && coords.count == 1 { continue }
                let point = MLNPointFeature()
                point.coordinate = coord
                point.attributes = ["name": index == 0 ? "出发" : "到达"]
                let source = MLNShapeSource(identifier: "node-\(index)", shape: point, options: nil)
                style.addSource(source)
                let circle = MLNCircleStyleLayer(identifier: "bubble-\(index)", source: source)
                circle.circleRadius = NSExpression(forConstantValue: index == 0 ? 27 : 35)
                circle.circleColor = NSExpression(forConstantValue: index == 0
                    ? UIColor(red: 0.51, green: 0.59, blue: 0.61, alpha: 1)
                    : UIColor(red: 0.93, green: 0.64, blue: 0.49, alpha: 1))
                circle.circleOpacity = NSExpression(forConstantValue: 0.38)
                circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                circle.circleStrokeWidth = NSExpression(forConstantValue: 1)
                style.addLayer(circle)
                let label = MLNSymbolStyleLayer(identifier: "label-\(index)", source: source)
                label.text = NSExpression(forKeyPath: "name")
                label.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
                label.textFontSize = NSExpression(forConstantValue: 12)
                label.textColor = NSExpression(forConstantValue: UIColor.darkGray)
                label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
                label.textHaloWidth = NSExpression(forConstantValue: 1)
                style.addLayer(label)
            }
            fit(mapView)
        }

        func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
            if fullyRendered { mapView.accessibilityIdentifier = "architectural-map-ready" }
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            DispatchQueue.main.async { self.parent.failed = true }
        }
    }
}

struct ArchitecturalMapLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            item("主干道", color: Color(red: 0.20, green: 0.31, blue: 0.47))
            item("次干道", color: Color(red: 0.64, green: 0.61, blue: 0.75))
            item("行程", color: Color(red: 0.12, green: 0.46, blue: 0.49))
        }
        .font(.caption2)
        .foregroundStyle(Color.black.opacity(0.7))
        .padding(8)
        .background(.white.opacity(0.9), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func item(_ text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Capsule().fill(color).frame(width: 14, height: 2)
            Text(text)
        }
    }
}
