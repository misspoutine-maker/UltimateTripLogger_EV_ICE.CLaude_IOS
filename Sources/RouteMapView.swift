import SwiftUI
import MapKit

final class StageAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let stageType: StageType

    init(stage: Stage) {
        coordinate = CLLocationCoordinate2D(latitude: stage.lat, longitude: stage.lng)
        title = stage.placeName.isEmpty ? stage.type.label : "\(stage.type.label) – \(stage.placeName)"
        stageType = stage.type
    }
}

struct RouteMapView: UIViewRepresentable {
    let points: [GpsPoint]
    let stages: [Stage]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        if coords.count >= 2 {
            map.addOverlay(MKPolyline(coordinates: coords, count: coords.count))
        }
        let valid = stages.filter { $0.lat != 0 || $0.lng != 0 }
        for s in valid { map.addAnnotation(StageAnnotation(stage: s)) }

        if coords.count >= 2 {
            let rect = MKPolyline(coordinates: coords, count: coords.count).boundingMapRect
            map.setVisibleMapRect(rect,
                                  edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30),
                                  animated: false)
        } else if let first = valid.first {
            let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng),
                                            latitudinalMeters: 5000, longitudinalMeters: 5000)
            map.setRegion(region, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor(red: 0, green: 0.82, blue: 1, alpha: 1)
                r.lineWidth = 4
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? StageAnnotation else { return nil }
            let id = "stage"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: a, reuseIdentifier: id)
            view.annotation = a
            view.canShowCallout = true
            view.glyphImage = UIImage(systemName: a.stageType.icon)
            switch a.stageType {
            case .charging, .chargingMeal: view.markerTintColor = .systemGreen
            case .meal: view.markerTintColor = .systemOrange
            case .other: view.markerTintColor = .systemPurple
            case .border: view.markerTintColor = .systemYellow
            default: view.markerTintColor = .systemBlue
            }
            return view
        }
    }
}
