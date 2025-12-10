//
//  VideoStreamView.swift
//  DroneControl
//
//  Live RTSP video stream with telemetry overlay
//  Stream URL: rtsp://192.168.4.1:554/stream (ESP32 WiFi)
//

import SwiftUI
import AVKit
import AVFoundation

// MARK: - Video Stream View
struct VideoStreamView: View {
    @ObservedObject var mavlinkManager: MAVLinkManager
    @StateObject private var videoPlayer = VideoPlayerManager()
    @State private var isFullscreen = false
    @State private var showControls = true
    @State private var currentTime = Date()
    
    // Timer for updating time
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Video Player
                VideoPlayerView(player: videoPlayer.player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipped()
                
                // Overlay Container
                VStack {
                    // Top Bar - Date/Time and Recording Indicator
                    HStack {
                        // Date Time Panel (Turkey Format)
                        DateTimeOverlay(currentTime: currentTime)
                        
                        Spacer()
                        
                        // Connection Status
                        ConnectionIndicator(
                            isConnected: mavlinkManager.isConnected,
                            isStreaming: videoPlayer.isPlaying
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    // Bottom Telemetry Panel
                    HStack(alignment: .bottom) {
                        // Left Side - Primary Flight Data
                        VideoTelemetryPanel(mavlinkManager: mavlinkManager)
                        
                        Spacer()
                        
                        // Right Side - Attitude Indicator Mini
                        MiniAttitudeOverlay(
                            roll: mavlinkManager.roll,
                            pitch: mavlinkManager.pitch,
                            heading: mavlinkManager.heading
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                
                // Center Controls (Play/Pause/Reconnect)
                if showControls {
                    VStack {
                        Spacer()
                        HStack(spacing: 30) {
                            // Reconnect Button
                            Button(action: {
                                videoPlayer.reconnect()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(.black.opacity(0.5))
                                    )
                            }
                            
                            // Play/Pause Button
                            Button(action: {
                                if videoPlayer.isPlaying {
                                    videoPlayer.pause()
                                } else {
                                    videoPlayer.play()
                                }
                            }) {
                                Image(systemName: videoPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        Circle()
                                            .fill(.cyan.opacity(0.8))
                                            .shadow(color: .cyan.opacity(0.5), radius: 10)
                                    )
                            }
                            
                            // Fullscreen Button
                            Button(action: {
                                isFullscreen.toggle()
                            }) {
                                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(.black.opacity(0.5))
                                    )
                            }
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }
                
                // No Signal Overlay
                if !videoPlayer.isPlaying && !videoPlayer.isConnecting {
                    NoSignalOverlay(onRetry: {
                        videoPlayer.reconnect()
                    })
                }
                
                // Loading Overlay
                if videoPlayer.isConnecting {
                    LoadingOverlay()
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls.toggle()
                }
            }
        }
        .onReceive(timer) { time in
            currentTime = time
        }
        .onAppear {
            videoPlayer.setupPlayer()
        }
        .onDisappear {
            videoPlayer.stop()
        }
    }
}

// MARK: - Video Player Manager
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isConnecting = false
    @Published var hasError = false
    
    private let rtspURL = "rtsp://192.168.4.1:554/stream"
    private var playerItem: AVPlayerItem?
    private var playerObserver: Any?
    
    func setupPlayer() {
        guard let url = URL(string: rtspURL) else {
            hasError = true
            return
        }
        
        isConnecting = true
        
        // Create asset with network options
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [:],
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Configure player
        player?.automaticallyWaitsToMinimizeStalling = false
        
        // Observe player status
        playerObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.isConnecting = false
                    self?.isPlaying = true
                    self?.player?.play()
                case .failed:
                    self?.isConnecting = false
                    self?.hasError = true
                    self?.isPlaying = false
                    print("Video stream error: \(item.error?.localizedDescription ?? "Unknown")")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        
        // Start playback attempt
        player?.play()
        
        // Timeout for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.isConnecting == true {
                self?.isConnecting = false
                self?.hasError = true
            }
        }
    }
    
    func play() {
        if player == nil {
            setupPlayer()
        } else {
            player?.play()
            isPlaying = true
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func stop() {
        player?.pause()
        player = nil
        playerItem = nil
        isPlaying = false
    }
    
    func reconnect() {
        stop()
        hasError = false
        setupPlayer()
    }
}

// MARK: - Video Player UIKit Wrapper
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - Date Time Overlay (Turkey Format)
struct DateTimeOverlay: View {
    let currentTime: Date
    
    private var turkeyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }
    
    private var turkeyTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text(turkeyDateFormatter.string(from: currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text(turkeyTimeFormatter.string(from: currentTime))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.6))
                .shadow(color: .black.opacity(0.3), radius: 4)
        )
    }
}

// MARK: - Connection Indicator
struct ConnectionIndicator: View {
    let isConnected: Bool
    let isStreaming: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // MAVLink Connection
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("MAV")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Video Stream
            HStack(spacing: 4) {
                Circle()
                    .fill(isStreaming ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("VID")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Recording indicator (if streaming)
            if isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)
                    Text("REC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.6))
        )
    }
}

// MARK: - Video Telemetry Panel
struct VideoTelemetryPanel: View {
    @ObservedObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // GPS Coordinates
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text(String(format: "%.5f, %.5f", mavlinkManager.latitude, mavlinkManager.longitude))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 12) {
                // Altitude
                TelemetryItem(
                    icon: "arrow.up.circle.fill",
                    value: String(format: "%.1fm", mavlinkManager.altitude),
                    color: .green
                )
                
                // Speed
                TelemetryItem(
                    icon: "speedometer",
                    value: String(format: "%.1fm/s", mavlinkManager.groundSpeed),
                    color: .orange
                )
                
                // Heading
                TelemetryItem(
                    icon: "safari.fill",
                    value: String(format: "%.0f°", mavlinkManager.heading),
                    color: .purple
                )
            }
            
            HStack(spacing: 12) {
                // Battery
                TelemetryItem(
                    icon: "bolt.fill",
                    value: String(format: "%.1fV", mavlinkManager.batteryVoltage),
                    color: batteryColor
                )
                
                // Satellites
                TelemetryItem(
                    icon: "antenna.radiowaves.left.and.right",
                    value: "\(mavlinkManager.gpsSatellites)",
                    color: gpsColor
                )
                
                // Flight Mode
                FlightModeTag(
                    isArmed: mavlinkManager.isArmed,
                    mode: mavlinkManager.droneState.flightMode
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.6))
                .shadow(color: .black.opacity(0.3), radius: 4)
        )
    }
    
    private var batteryColor: Color {
        if mavlinkManager.batteryVoltage < 10.5 { return .red }
        if mavlinkManager.batteryVoltage < 11.1 { return .orange }
        return .green
    }
    
    private var gpsColor: Color {
        if mavlinkManager.gpsSatellites >= 8 { return .green }
        if mavlinkManager.gpsSatellites >= 5 { return .orange }
        return .red
    }
}

// MARK: - Telemetry Item
struct TelemetryItem: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Flight Mode Tag
struct FlightModeTag: View {
    let isArmed: Bool
    let mode: CopterFlightMode
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isArmed ? Color.red : Color.gray)
                .frame(width: 6, height: 6)
            Text(mode.name.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(mode.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(.black.opacity(0.4))
        )
    }
}

// MARK: - Mini Attitude Overlay
struct MiniAttitudeOverlay: View {
    let roll: Float
    let pitch: Float
    let heading: Float
    
    var body: some View {
        VStack(spacing: 4) {
            // Attitude Ball (simplified)
            ZStack {
                Circle()
                    .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                    .frame(width: 60, height: 60)
                
                // Horizon line
                Rectangle()
                    .fill(Color.cyan)
                    .frame(width: 40, height: 2)
                    .rotationEffect(.degrees(Double(roll)))
                    .offset(y: CGFloat(pitch) * 0.3)
                
                // Center reference
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            
            // Values
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text("R")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                    Text(String(format: "%.0f°", roll))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 0) {
                    Text("P")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                    Text(String(format: "%.0f°", pitch))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 0) {
                    Text("H")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                    Text(String(format: "%.0f°", heading))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.6))
        )
    }
}

// MARK: - No Signal Overlay
struct NoSignalOverlay: View {
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Video Sinyali Yok")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text("rtsp://192.168.4.1:554/stream")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
            
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Yeniden Bağlan")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.cyan)
                )
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.8))
        )
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.cyan, lineWidth: 4)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
            
            Text("Bağlanıyor...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.8))
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview
#Preview {
    VideoStreamView(mavlinkManager: MAVLinkManager.shared)
}
