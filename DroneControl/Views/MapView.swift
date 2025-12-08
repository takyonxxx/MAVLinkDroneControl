//
//  MapView.swift
//  DroneControl
//
//  Satellite map view with real-time drone tracking and telemetry overlay
//

import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var mavlinkManager: MAVLinkManager
    @StateObject private var mapViewModel = MapViewModel()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9334, longitude: 32.8597), // Ankara default
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            // Satellite Map
            Map(coordinateRegion: $region,
                interactionModes: [.pan, .zoom],
                showsUserLocation: false,
                annotationItems: mapViewModel.droneLocations) { location in
                MapAnnotation(coordinate: location.coordinate) {
                    DroneMarker(heading: location.heading)
                }
            }
            .ignoresSafeArea()
            
            // Telemetry Overlay Panel
            VStack {
                HStack {
                    Spacer()
                    TelemetryPanel(mavlinkManager: mavlinkManager)
                        .padding(.trailing, 16)
                        .padding(.top, 60)
                }
                Spacer()
            }
            
            // Clear Map Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation {
                            mapViewModel.clearFlightPath()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                            Text("Clear Path")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        )
                        .foregroundColor(.white)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 40)
                }
            }
            
            // Center on Drone Button
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        centerOnDrone()
                    }) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 40)
                    Spacer()
                }
            }
        }
        .onChange(of: mavlinkManager.latitude) { _ in updateDroneLocation() }
        .onChange(of: mavlinkManager.longitude) { _ in updateDroneLocation() }
        .onChange(of: mavlinkManager.heading) { _ in updateDroneLocation() }
        .onAppear {
            centerOnDrone()
        }
    }
    
    private func updateDroneLocation() {
        let coordinate = CLLocationCoordinate2D(
            latitude: mavlinkManager.latitude,
            longitude: mavlinkManager.longitude
        )
        
        // Only update if we have valid GPS coordinates
        guard coordinate.latitude != 0 && coordinate.longitude != 0 else { return }
        
        mapViewModel.addDroneLocation(
            coordinate: coordinate,
            heading: Double(mavlinkManager.heading)
        )
    }
    
    private func centerOnDrone() {
        guard mavlinkManager.latitude != 0 && mavlinkManager.longitude != 0 else { return }
        
        withAnimation {
            region.center = CLLocationCoordinate2D(
                latitude: mavlinkManager.latitude,
                longitude: mavlinkManager.longitude
            )
        }
    }
}

// MARK: - Drone Marker
struct DroneMarker: View {
    let heading: Double
    
    var body: some View {
        ZStack {
            // Shadow/glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.6), Color.cyan.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
            
            // Drone icon
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 42, height: 42)
                )
                .rotationEffect(.degrees(heading))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Map View Model
class MapViewModel: ObservableObject {
    @Published var droneLocations: [DroneLocation] = []
    @Published var flightPath: [CLLocationCoordinate2D] = []
    
    private let maxPathPoints = 500 // Limit path points for performance
    
    func addDroneLocation(coordinate: CLLocationCoordinate2D, heading: Double) {
        // Update current drone location
        let location = DroneLocation(id: UUID(), coordinate: coordinate, heading: heading)
        
        // Keep only the latest position for the drone marker
        if droneLocations.isEmpty {
            droneLocations = [location]
        } else {
            droneLocations[0] = location
        }
        
        // Add to flight path
        flightPath.append(coordinate)
        
        // Limit path points
        if flightPath.count > maxPathPoints {
            flightPath.removeFirst(flightPath.count - maxPathPoints)
        }
    }
    
    func clearFlightPath() {
        flightPath.removeAll()
    }
}
