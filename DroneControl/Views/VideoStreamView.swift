//
//  VideoStreamView.swift
//  DroneControl
//
//  Live RTSP video stream with telemetry overlay
//  Stream URL configurable via Settings (saved in UserDefaults)
//

import SwiftUI
import AVKit
import AVFoundation

// MARK: - Video Stream View
struct VideoStreamView: View {
    @ObservedObject var mavlinkManager: MAVLinkManager
    @StateObject private var videoPlayer = VideoPlayerManager()
    @StateObject private var settings = SettingsManager.shared
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
                    NoSignalOverlay(
                        currentURL: settings.rtspURL,
                        onRetry: {
                            videoPlayer.reconnect()
                        }
                    )
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
            videoPlayer.setupPlayer(url: settings.rtspURL)
        }
        .onDisappear {
            videoPlayer.stop()
        }
        .onChange(of: settings.rtspURL) { newURL in
            // URL changed in settings, reconnect with new URL
            videoPlayer.reconnect(newURL: newURL)
        }
    }
}

// MARK: - Video Player Manager
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isConnecting = false
    @Published var hasError = false
    
    private var currentRTSPURL = ""
    private var playerItem: AVPlayerItem?
    private var playerObserver: Any?
    
    func setupPlayer(url: String) {
        currentRTSPURL = url
        
        guard let videoURL = URL(string: url) else {
            hasError = true
            return
        }
        
        isConnecting = true
        
        // Create asset with network options
        let asset = AVURLAsset(url: videoURL, options: [
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
            setupPlayer(url: currentRTSPURL)
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
        isConnecting = false
    }
    
    func reconnect(newURL: String? = nil) {
        stop()
        
        // Wait a bit before reconnecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let url = newURL {
                self?.setupPlayer(url: url)
            } else if let currentURL = self?.currentRTSPURL {
                self?.setupPlayer(url: currentURL)
            }
        }
    }
    
    deinit {
        stop()
    }
}

// MARK: - Video Player View (UIKit/AppKit Bridge)
struct VideoPlayerView: View {
    let player: AVPlayer?
    
    var body: some View {
        if let player = player {
            #if os(iOS)
            VideoPlayerUIView(player: player)
            #else
            VideoPlayerNSView(player: player)
            #endif
        } else {
            Color.black
        }
    }
}

#if os(iOS)
import UIKit

struct VideoPlayerUIView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}
#else
import AppKit

struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = nsView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}
#endif

// MARK: - Date Time Overlay
struct DateTimeOverlay: View {
    let currentTime: Date
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateFormatter.string(from: currentTime))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            
            Text(timeFormatter.string(from: currentTime))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.6))
        )
    }
}

// MARK: - Connection Indicator
struct ConnectionIndicator: View {
    let isConnected: Bool
    let isStreaming: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // MAVLink Status
            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: isConnected ? .green : .red, radius: 4)
                
                Text("MAVLink")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Stream Status
            HStack(spacing: 4) {
                Circle()
                    .fill(isStreaming ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: isStreaming ? .green : .red, radius: 4)
                
                Text("Video")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Altitude
                TelemetryItem(
                    icon: "arrow.up",
                    value: String(format: "%.1fm", mavlinkManager.altitude),
                    color: .cyan
                )
                
                // Speed
                TelemetryItem(
                    icon: "speedometer",
                    value: String(format: "%.1fm/s", mavlinkManager.groundSpeed),
                    color: .green
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
    let currentURL: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Video Sinyali Yok")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text(currentURL)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
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
