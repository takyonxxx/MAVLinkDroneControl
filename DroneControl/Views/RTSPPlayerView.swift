//
//  RTSPPlayerView.swift
//  DroneControl
//
//  RTSP Video Player - SIMPLE FULLSCREEN FIX
//

import SwiftUI
import MobileVLCKit

// MARK: - RTSP Player SwiftUI View
struct RTSPPlayerView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var playerController = RTSPPlayerController()
    @ObservedObject var mavlinkManager: MAVLinkManager
    @State private var isFullScreen = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        GeometryReader { geometry in
            mainContentView(geometry: geometry)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !isFullScreen {
                    Text(settings.rtspURL)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .navigationBarBackButtonHidden(isFullScreen)
        .statusBar(hidden: isFullScreen)
        .persistentSystemOverlays(isFullScreen ? .hidden : .automatic)
        .ignoresSafeArea(isFullScreen ? .all : [])
        .onAppear {
            playerController.play(url: settings.rtspURL)
        }
        .onDisappear {
            playerController.stop()
        }
        .onChange(of: settings.rtspURL) { _, newURL in
            playerController.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                playerController.play(url: newURL)
            }
        }
    }
    
    private func mainContentView(geometry: GeometryProxy) -> some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                videoSection(geometry: geometry)
                
                if !isFullScreen {
                    statusBar
                    controlsView.padding()
                    infoCard.padding(.horizontal)
                    Spacer()
                }
            }
        }
    }
    
    private func videoSection(geometry: GeometryProxy) -> some View {
        ZStack {
            videoPlayerBase(geometry: geometry)
                .overlay(bufferingOverlay)
                .overlay(fullscreenControlsOverlay)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isFullScreen.toggle()
                    }
                }
        }
        .padding(.horizontal, isFullScreen ? 0 : 16)
        .padding(.top, isFullScreen ? 0 : 16)
    }
    
    private func videoPlayerBase(geometry: GeometryProxy) -> some View {
        let videoAspectRatio: CGFloat = {
            if let resolution = playerController.videoResolution,
               resolution.width > 0, resolution.height > 0 {
                return resolution.width / resolution.height
            }
            return 16.0 / 9.0 // Default aspect ratio
        }()
        
        return ZStack(alignment: .topTrailing) {
            // Video Layer
            RTSPVideoView(controller: playerController)
                .background(Color.black)
            
            // Overlay Layer - SAME aspect ratio as video
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        // Altitude
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                            Text(String(format: "%.1f m", Double(mavlinkManager.altitude)))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                        }
                        
                        // Ground Speed
                        HStack(spacing: 6) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.cyan)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                            Text(String(format: "%.1f m/s", Double(mavlinkManager.groundSpeed)))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                        }
                        
                        // Battery
                        HStack(spacing: 6) {
                            Image(systemName: batteryIcon(percent: mavlinkManager.batteryRemaining))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(batteryColor(percent: mavlinkManager.batteryRemaining))
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                            Text(String(format: "%.1fV (%d%%)", Double(mavlinkManager.batteryVoltage), mavlinkManager.batteryRemaining))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                        }
                        
                        // GPS Satellites
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                            Text("\(mavlinkManager.gpsSatellites)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 3, x: 0, y: 0)
                        }
                        
                        // Flight Mode
                        Text(mavlinkManager.droneState.flightMode.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                            .shadow(color: .black, radius: 3, x: 0, y: 0)
                        
                        // Video Resolution & FPS
                        if let resolution = playerController.videoResolution,
                           let fps = playerController.currentFPS {
                            HStack(spacing: 6) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.purple)
                                    .shadow(color: .black, radius: 3, x: 0, y: 0)
                                Text("\(Int(resolution.width))x\(Int(resolution.height)) @ \(String(format: "%.0f", fps)) fps")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white)
                                    .shadow(color: .black, radius: 3, x: 0, y: 0)
                            }
                        }
                        
                        // Video Codec
                        if let codec = playerController.videoCodec {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.green)
                                    .shadow(color: .black, radius: 3, x: 0, y: 0)
                                Text(codec)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                                    .shadow(color: .black, radius: 3, x: 0, y: 0)
                            }
                        }
                    }
                    .padding(12)
                }
                Spacer()
            }
        }
        .aspectRatio(videoAspectRatio, contentMode: .fit)
        .cornerRadius(isFullScreen ? 0 : 12)
        .frame(
            width: isFullScreen ? geometry.size.width : nil,
            height: isFullScreen ? geometry.size.height : nil,
            alignment: .center
        )
    }
    
    
    private func batteryIcon(percent: Int) -> String {
        if percent > 75 { return "battery.100" }
        else if percent > 50 { return "battery.75" }
        else if percent > 25 { return "battery.50" }
        else if percent > 10 { return "battery.25" }
        else { return "battery.0" }
    }
    
    private func batteryColor(percent: Int) -> Color {
        if percent > 50 { return .green }
        else if percent > 25 { return .yellow }
        else { return .red }
    }
    
    private var bufferingOverlay: some View {
        Group {
            if playerController.isBuffering && !playerController.isPlaying {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Buffering...")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                }
            }
        }
    }
    
    private var fullscreenControlsOverlay: some View {
        Group {
            if isFullScreen {
                VStack {
                    Spacer()
                    HStack {
                        exitFullscreenButton
                        Spacer()
                    }
                }
            }
        }
    }
    
    private var exitFullscreenButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isFullScreen = false
            }
        }) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .clipShape(Circle())
        }
        .padding()
    }
    
    var statusBar: some View {
        HStack {
            Circle()
                .fill(playerController.statusColor)
                .frame(width: 10, height: 10)
            
            Text(playerController.statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
    }
    
    var controlsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: {
                    playerController.play(url: settings.rtspURL)
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(playerController.isPlaying ? Color.gray : Color.green)
                    .cornerRadius(10)
                }
                .disabled(playerController.isPlaying)
                
                Button(action: {
                    playerController.pause()
                }) {
                    HStack {
                        Image(systemName: "pause.fill")
                        Text("Pause")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    playerController.stop()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .cornerRadius(10)
                }
            }
            
            HStack(spacing: 12) {
                Toggle("Low Latency", isOn: $playerController.useLowLatency)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .onChange(of: playerController.useLowLatency) { _, _ in
                        if playerController.isPlaying {
                            playerController.stop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                playerController.play(url: settings.rtspURL)
                            }
                        }
                    }
                
                Toggle("HW Decode", isOn: $playerController.useHardwareDecoding)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .onChange(of: playerController.useHardwareDecoding) { _, _ in
                        if playerController.isPlaying {
                            playerController.stop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                playerController.play(url: settings.rtspURL)
                            }
                        }
                    }
            }
            .padding(.horizontal)
        }
    }
    
    var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.cyan)
                Text("Kullanım")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• Çift tıkla: Tam ekran")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Text("• Low Latency: Kapalı önerilir")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Text("• HW Decode: Donanım hızlandırma")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
}

// MARK: - Video Codec Detector
class VideoCodecDetector {
    static func detectCodec(from fourCC: String?, codecName: String?, description: String?) -> String? {
        if let codec = detectFromFourCC(fourCC) ?? detectFromCodecName(codecName) ?? detectFromDescription(description) {
            return codec
        }
        return nil
    }
    
    private static func detectFromFourCC(_ fourCC: String?) -> String? {
        guard let fourCC = fourCC?.lowercased() else { return nil }
        let codecMap: [String: String] = [
            "h264": "H.264", "avc1": "H.264", "avc": "H.264",
            "h265": "H.265/HEVC", "hevc": "H.265/HEVC",
            "mjpg": "MJPEG", "mjpeg": "MJPEG"
        ]
        return codecMap[fourCC]
    }
    
    private static func detectFromCodecName(_ name: String?) -> String? {
        guard let name = name?.lowercased() else { return nil }
        if name.contains("h264") || name.contains("avc") { return "H.264" }
        if name.contains("h265") || name.contains("hevc") { return "H.265/HEVC" }
        if name.contains("mjpeg") { return "MJPEG" }
        return nil
    }
    
    private static func detectFromDescription(_ description: String?) -> String? {
        guard let description = description?.lowercased() else { return nil }
        if description.contains("h.264") || description.contains("h264") { return "H.264" }
        if description.contains("h.265") || description.contains("h265") { return "H.265/HEVC" }
        return nil
    }
}

// MARK: - RTSP Player Controller
class RTSPPlayerController: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var statusText = "Ready"
    @Published var statusColor: Color = .gray
    @Published var currentFPS: Double? = nil
    @Published var videoResolution: CGSize? = nil
    @Published var currentBitrate: Double? = nil
    @Published var videoCodec: String? = nil
    @Published var useLowLatency = false
    @Published var useHardwareDecoding = true
    
    var mediaPlayer: VLCMediaPlayer?
    private weak var videoView: UIView?
    
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    private var lastDisplayedPictures: Int32 = 0
    private var lastBitrateBytes: Int32 = 0
    private var lastBitrateUpdate = Date()
    private var statsUpdateTimer: Timer?
    private var codecDetectionAttempts = 0
    private let maxCodecDetectionAttempts = 5
    private var bufferingClearTimer: Timer?
    
    override init() {
        super.init()
        setupPlayer()
    }
    
    private func setupPlayer() {
        DispatchQueue.main.async {
            self.mediaPlayer = VLCMediaPlayer()
            self.mediaPlayer?.delegate = self
        }
        
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatistics()
        }
    }
    
    func setVideoView(_ view: UIView) {
        self.videoView = view
        DispatchQueue.main.async {
            self.mediaPlayer?.drawable = view
        }
    }
    
    func play(url: String) {
        guard let player = mediaPlayer else { return }
        guard let videoURL = URL(string: url) else {
            DispatchQueue.main.async {
                self.statusText = "Invalid URL"
                self.statusColor = .red
            }
            return
        }
        
        DispatchQueue.main.async {
            player.stop()
            
            self.videoResolution = nil
            self.currentFPS = nil
            self.currentBitrate = nil
            self.videoCodec = nil
            self.codecDetectionAttempts = 0
        }
        
        let media = VLCMedia(url: videoURL)
        
        if useLowLatency {
            media.addOption(":network-caching=150")
            media.addOption(":live-caching=150")
            media.addOption(":file-caching=150")
        } else {
            media.addOption(":network-caching=300")
            media.addOption(":live-caching=300")
            media.addOption(":file-caching=300")
        }
        
        media.addOption(":rtsp-tcp")
        media.addOption(":no-audio")
        media.addOption(":clock-jitter=0")
        
        if useHardwareDecoding {
            media.addOption(":avcodec-hw=videotoolbox")
        } else {
            media.addOption(":avcodec-hw=none")
        }
        
        media.addOption(":verbose=0")
        
        DispatchQueue.main.async {
            player.media = media
            player.play()
            
            self.isBuffering = true
            self.statusText = "Connecting..."
            self.statusColor = .orange
            self.frameCount = 0
            self.lastFPSUpdate = Date()
            self.lastDisplayedPictures = 0
            self.lastBitrateBytes = 0
            self.lastBitrateUpdate = Date()
            
            self.bufferingClearTimer?.invalidate()
            self.bufferingClearTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                if self?.isBuffering == true {
                    self?.isBuffering = false
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.detectVideoProperties()
        }
    }
    
    func pause() {
        DispatchQueue.main.async {
            self.mediaPlayer?.pause()
        }
    }
    
    func stop() {
        bufferingClearTimer?.invalidate()
        
        DispatchQueue.main.async {
            self.mediaPlayer?.stop()
            self.isPlaying = false
            self.isBuffering = false
            self.statusText = "Stopped"
            self.statusColor = .gray
            self.currentFPS = nil
            self.videoResolution = nil
            self.currentBitrate = nil
            self.videoCodec = nil
        }
    }
    
    private func detectVideoProperties() {
        guard let player = mediaPlayer, let media = player.media else { return }
        guard codecDetectionAttempts < maxCodecDetectionAttempts else { return }
        
        codecDetectionAttempts += 1
        
        if player.videoSize.width > 0 && player.videoSize.height > 0 {
            DispatchQueue.main.async {
                self.videoResolution = player.videoSize
            }
        }
        
        if let tracks = media.tracksInformation as? [[String: Any]] {
            for track in tracks {
                if let type = track["Type"] as? String, type == "video" {
                    let codecFourCC = track["Codec"] as? String
                    let codecName = track["CodecName"] as? String
                    let description = track["Description"] as? String
                    
                    if let detectedCodec = VideoCodecDetector.detectCodec(
                        from: codecFourCC,
                        codecName: codecName,
                        description: description
                    ) {
                        DispatchQueue.main.async {
                            self.videoCodec = detectedCodec
                        }
                    }
                    
                    if self.videoResolution == nil {
                        if let width = track["Width"] as? CGFloat,
                           let height = track["Height"] as? CGFloat {
                            DispatchQueue.main.async {
                                self.videoResolution = CGSize(width: width, height: height)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateStatistics() {
        guard let player = mediaPlayer, player.isPlaying else { return }
        
        let now = Date()
        
        // Get statistics from VLC
        guard let media = player.media else { return }
        let statistics = media.statistics
        
        // Calculate FPS from displayed pictures
        let currentDisplayedPictures = statistics.displayedPictures
        let fpsElapsed = now.timeIntervalSince(lastFPSUpdate)
        
        if fpsElapsed >= 1.0 && lastDisplayedPictures > 0 {
            let framesDiff = Double(currentDisplayedPictures - lastDisplayedPictures)
            let fps = framesDiff / fpsElapsed
            
            DispatchQueue.main.async {
                self.currentFPS = fps
            }
            
            lastDisplayedPictures = currentDisplayedPictures
            lastFPSUpdate = now
        } else if lastDisplayedPictures == 0 {
            // First time, just set the baseline
            lastDisplayedPictures = currentDisplayedPictures
            lastFPSUpdate = now
        }
        
        // Calculate bitrate - FIXED
        let currentBytes = statistics.decodedVideo + statistics.decodedAudio
        let bitrateElapsed = now.timeIntervalSince(lastBitrateUpdate)
        
        if bitrateElapsed >= 1.0 {
            if lastBitrateBytes > 0 {
                // Calculate from difference
                let bytesPerSecond = Double(currentBytes - lastBitrateBytes) / bitrateElapsed
                let megabitsPerSecond = (bytesPerSecond * 8.0) / 1_000_000.0
                
                DispatchQueue.main.async {
                    self.currentBitrate = megabitsPerSecond
                }
            }
            
            lastBitrateBytes = currentBytes
            lastBitrateUpdate = now
        } else if lastBitrateBytes == 0 && currentBytes > 0 {
            // First measurement
            lastBitrateBytes = currentBytes
            lastBitrateUpdate = now
        }
        
        // Detect video properties if still missing
        if videoCodec == nil && codecDetectionAttempts < maxCodecDetectionAttempts {
            detectVideoProperties()
        }
    }
    
    deinit {
        statsUpdateTimer?.invalidate()
        bufferingClearTimer?.invalidate()
    }
}

// MARK: - VLCMediaPlayerDelegate
extension RTSPPlayerController: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        
        DispatchQueue.main.async {
            switch player.state {
            case .playing:
                self.isPlaying = true
                self.isBuffering = false
                self.bufferingClearTimer?.invalidate()
                self.statusText = "Playing"
                self.statusColor = .green
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.detectVideoProperties()
                }
                
            case .buffering:
                if !self.isPlaying {
                    self.isBuffering = true
                    self.statusText = "Buffering..."
                    self.statusColor = .orange
                }
                
            case .error:
                self.isPlaying = false
                self.isBuffering = false
                self.bufferingClearTimer?.invalidate()
                self.statusText = "Error"
                self.statusColor = .red
                
            case .stopped:
                self.isPlaying = false
                self.isBuffering = false
                self.bufferingClearTimer?.invalidate()
                self.statusText = "Stopped"
                self.statusColor = .gray
                self.currentFPS = nil
                self.videoResolution = nil
                self.currentBitrate = nil
                
            case .paused:
                self.isPlaying = false
                self.statusText = "Paused"
                self.statusColor = .orange
                
            case .opening:
                self.statusText = "Opening..."
                self.statusColor = .orange
                
            case .ended:
                self.isPlaying = false
                self.isBuffering = false
                self.statusText = "Ended"
                self.statusColor = .gray
                
            @unknown default:
                break
            }
        }
    }
}

// MARK: - UIViewRepresentable
struct RTSPVideoView: UIViewRepresentable {
    @ObservedObject var controller: RTSPPlayerController
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        DispatchQueue.main.async {
            self.controller.setVideoView(view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // NO-OP: Important! Don't recreate view
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        RTSPPlayerView(mavlinkManager: MAVLinkManager())
    }
}
