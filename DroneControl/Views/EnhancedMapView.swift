//
//  EnhancedMapView.swift
//  DroneControl
//

import SwiftUI
import MapKit

struct EnhancedMapView: View {
    @ObservedObject var mavlinkManager: MAVLinkManager
    @StateObject private var mapViewModel = EnhancedMapViewModel()
    @State private var isFollowing = true
    
    var body: some View {
        ZStack {
            MapKitView(mapViewModel: mapViewModel, mavlinkManager: mavlinkManager)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    TelemetryPanel(mavlinkManager: mavlinkManager)
                        .padding(.trailing, 12)
                        .padding(.top, 10)
                }
                Spacer()
            }
            
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button(action: {
                        isFollowing.toggle()
                        if isFollowing {
                            mapViewModel.centerOnDrone()
                        }
                    }) {
                        Image(systemName: isFollowing ? "location.fill" : "location.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isFollowing ? .cyan : .white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.3))
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            )
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            mapViewModel.clearFlightPath()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14))
                            Text("Clear")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.3))
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        )
                        .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 30)
            }
        }
        .onChange(of: mavlinkManager.latitude) { _ in
            updateDroneLocation()
            if isFollowing {
                mapViewModel.centerOnDrone()
            }
        }
        .onChange(of: mavlinkManager.longitude) { _ in
            updateDroneLocation()
            if isFollowing {
                mapViewModel.centerOnDrone()
            }
        }
        .onChange(of: mavlinkManager.heading) { _ in updateDroneLocation() }
    }
    
    private func updateDroneLocation() {
        let coordinate = CLLocationCoordinate2D(
            latitude: mavlinkManager.latitude,
            longitude: mavlinkManager.longitude
        )
        
        guard coordinate.latitude != 0 && coordinate.longitude != 0 else { return }
        
        mapViewModel.addDroneLocation(
            coordinate: coordinate,
            heading: Double(mavlinkManager.heading)
        )
    }
}

struct MapKitView: UIViewRepresentable {
    @ObservedObject var mapViewModel: EnhancedMapViewModel
    @ObservedObject var mavlinkManager: MAVLinkManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satellite
        mapView.showsCompass = true
        mapView.showsScale = true
        
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9334, longitude: 32.8597),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: false)
        
        context.coordinator.mapView = mapView
        mapViewModel.setMapView(mapView)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let oldOverlays = mapView.overlays.filter { $0 is MKPolyline }
        mapView.removeOverlays(oldOverlays)
        
        if mapViewModel.flightPath.count > 1 {
            let polyline = MKPolyline(coordinates: mapViewModel.flightPath, count: mapViewModel.flightPath.count)
            mapView.addOverlay(polyline)
        }
        
        let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(oldAnnotations)
        
        if let droneLocation = mapViewModel.currentDroneLocation {
            let annotation = DroneAnnotation(
                coordinate: droneLocation.coordinate,
                heading: droneLocation.heading
            )
            mapView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitView
        var mapView: MKMapView?
        
        init(_ parent: MapKitView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.9)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let droneAnnotation = annotation as? DroneAnnotation else {
                return nil
            }
            
            let identifier = "DroneAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
            } else {
                annotationView?.annotation = annotation
            }
            
            let droneImage = createDroneImage(heading: droneAnnotation.heading)
            annotationView?.image = droneImage
            annotationView?.centerOffset = CGPoint(x: 0, y: 0)
            
            return annotationView
        }
        
        private func createDroneImage(heading: Double) -> UIImage {
            let size = CGSize(width: 60, height: 60)
            let renderer = UIGraphicsImageRenderer(size: size)
            
            return renderer.image { context in
                let ctx = context.cgContext
                
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        UIColor.cyan.withAlphaComponent(0.6).cgColor,
                        UIColor.cyan.withAlphaComponent(0.0).cgColor
                    ] as CFArray,
                    locations: [0.0, 1.0]
                )!
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width/2, y: size.height/2),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width/2, y: size.height/2),
                    endRadius: size.width/2,
                    options: []
                )
                
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: CGFloat(heading * .pi / 180))
                ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
                
                let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
                let droneIcon = UIImage(systemName: "airplane.circle.fill", withConfiguration: config)?
                    .withTintColor(.cyan, renderingMode: .alwaysOriginal)
                
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: 9, y: 9, width: 42, height: 42))
                
                droneIcon?.draw(in: CGRect(x: 12, y: 12, width: 36, height: 36))
            }
        }
    }
}

class DroneAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var heading: Double
    
    init(coordinate: CLLocationCoordinate2D, heading: Double) {
        self.coordinate = coordinate
        self.heading = heading
        super.init()
    }
}

class EnhancedMapViewModel: ObservableObject {
    @Published var currentDroneLocation: DroneLocation?
    @Published var flightPath: [CLLocationCoordinate2D] = []
    
    private weak var mapView: MKMapView?
    private let maxPathPoints = 1000
    private let minDistanceBetweenPoints: CLLocationDistance = 1.0
    
    func setMapView(_ mapView: MKMapView) {
        self.mapView = mapView
    }
    
    func addDroneLocation(coordinate: CLLocationCoordinate2D, heading: Double) {
        currentDroneLocation = DroneLocation(
            id: UUID(),
            coordinate: coordinate,
            heading: heading
        )
        
        if shouldAddToPath(coordinate) {
            flightPath.append(coordinate)
            
            if flightPath.count > maxPathPoints {
                flightPath.removeFirst(flightPath.count - maxPathPoints)
            }
        }
    }
    
    private func shouldAddToPath(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let lastCoordinate = flightPath.last else { return true }
        
        let lastLocation = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
        let newLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        return lastLocation.distance(from: newLocation) >= minDistanceBetweenPoints
    }
    
    func centerOnDrone() {
        guard let location = currentDroneLocation else { return }
        
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        mapView?.setRegion(region, animated: true)
    }
    
    func clearFlightPath() {
        flightPath.removeAll()
    }
}
