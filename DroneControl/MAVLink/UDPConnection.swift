//
//  UDPConnection.swift
//  DroneControl
//

import Foundation

class UDPConnection: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectionState: String = "Bağlantı Yok"
    
    private var socketFD: Int32 = -1
    private var receiveThread: Thread?
    private var isRunning = false
    
    private var remoteHost: String
    private var remotePort: UInt16
    private var localPort: UInt16
    
    private var remoteAddr: sockaddr_in?
    private let socketQueue = DispatchQueue(label: "com.dronecontrol.socket", qos: .userInitiated)
    
    private var sessionTargets: [String: sockaddr_in] = [:]
    private let sessionTargetsLock = NSLock()
    
    var onDataReceived: ((Data) -> Void)?
    var onConnectionStatusChanged: ((Bool) -> Void)?
    
    init(host: String = "192.168.4.1", port: UInt16 = 14550, localPort: UInt16 = 14550) {
        self.remoteHost = host
        self.remotePort = port
        self.localPort = localPort
    }
    
    deinit {
        disconnect()
    }
    
    func updateEndpoint(host: String, port: UInt16) {
        self.remoteHost = host
        self.remotePort = port
        
        if isConnected {
            disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.connect()
            }
        }
    }
    
    func connect() {
        print("🔌 Connecting UDP socket...")
        
        socketQueue.async {
            self.socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            
            guard self.socketFD >= 0 else {
                print("❌ Failed to create socket: \(String(cString: strerror(errno)))")
                return
            }
            
            var reuseAddr: Int32 = 1
            setsockopt(self.socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
            
            #if os(macOS)
            var reusePort: Int32 = 1
            setsockopt(self.socketFD, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout<Int32>.size))
            #endif
            
            var localAddr = sockaddr_in()
            localAddr.sin_family = sa_family_t(AF_INET)
            localAddr.sin_port = self.localPort.bigEndian
            localAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
            
            let bindResult = withUnsafePointer(to: &localAddr) { localAddrPtr in
                localAddrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    bind(self.socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if bindResult < 0 {
                print("❌ Failed to bind socket: \(String(cString: strerror(errno)))")
                close(self.socketFD)
                return
            }
            
            print("✅ Socket bound to 0.0.0.0:\(self.localPort)")
            
            var flags = fcntl(self.socketFD, F_GETFL, 0)
            flags |= O_NONBLOCK
            fcntl(self.socketFD, F_SETFL, flags)
            
            var remoteAddr = sockaddr_in()
            remoteAddr.sin_family = sa_family_t(AF_INET)
            remoteAddr.sin_port = self.remotePort.bigEndian
            
            let hostAddr = self.remoteHost.withCString { cString in
                inet_addr(cString)
            }
            
            if hostAddr != INADDR_NONE {
                remoteAddr.sin_addr.s_addr = hostAddr
            } else {
                print("❌ Invalid remote host address")
                return
            }
            
            self.remoteAddr = remoteAddr
            
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectionState = "Bağlı"
                self.onConnectionStatusChanged?(true)
                print("✅ UDP connection established")
            }
            
            self.isRunning = true
            self.receiveThread = Thread { [weak self] in
                self?.receiveLoop()
            }
            self.receiveThread?.start()
        }
    }
    
    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var lastDataTime = Date()
        
        while isRunning {
            var senderAddr = sockaddr_in()
            var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let bytesReceived = withUnsafeMutablePointer(to: &senderAddr) { senderPtr in
                senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    recvfrom(self.socketFD, &buffer, buffer.count, 0, sockaddrPtr, &senderLen)
                }
            }
            
            if bytesReceived > 0 {
                lastDataTime = Date()
                let data = Data(bytes: buffer, count: bytesReceived)
                
                let senderIP = senderAddr.sin_addr.s_addr
                let senderPort = UInt16(bigEndian: senderAddr.sin_port)
                let senderIPString = String(format: "%d.%d.%d.%d",
                    (senderIP) & 0xFF,
                    (senderIP >> 8) & 0xFF,
                    (senderIP >> 16) & 0xFF,
                    (senderIP >> 24) & 0xFF)
                
                let sessionKey = "\(senderIPString):\(senderPort)"
                sessionTargetsLock.lock()
                if sessionTargets[sessionKey] == nil {
                    sessionTargets[sessionKey] = senderAddr
                }
                sessionTargetsLock.unlock()
                
                DispatchQueue.main.async { [weak self] in
                    self?.onDataReceived?(data)
                }
            } else if bytesReceived < 0 {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    let elapsed = Date().timeIntervalSince(lastDataTime)
                    if elapsed > 5.0 && !isRunning {
                        print("⚠️ No data received for 5 seconds")
                    }
                    usleep(10000)
                } else {
                    print("❌ Receive error: \(String(cString: strerror(err)))")
                    break
                }
            }
        }
    }
    
    func send(_ data: Data) {
        guard isConnected, socketFD >= 0 else { return }
        
        socketQueue.async {
            guard var addr = self.remoteAddr else { return }
            
            let primaryResult = data.withUnsafeBytes { bufferPtr in
                withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        sendto(self.socketFD, bufferPtr.baseAddress, data.count, 0,
                               sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            
            if primaryResult < 0 {
                print("❌ Send error: \(String(cString: strerror(errno)))")
            }
            
            self.sessionTargetsLock.lock()
            let targets = self.sessionTargets
            self.sessionTargetsLock.unlock()
            
            for (_, var sessionAddr) in targets {
                if sessionAddr.sin_addr.s_addr == addr.sin_addr.s_addr &&
                   sessionAddr.sin_port == addr.sin_port {
                    continue
                }
                
                let _ = data.withUnsafeBytes { bufferPtr in
                    withUnsafePointer(to: &sessionAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                            sendto(self.socketFD, bufferPtr.baseAddress, data.count, 0,
                                   sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
        }
    }
    
    func disconnect() {
        print("🔌 Disconnecting...")
        
        isRunning = false
        
        if let thread = receiveThread {
            thread.cancel()
            receiveThread = nil
        }
        
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        
        sessionTargetsLock.lock()
        sessionTargets.removeAll()
        sessionTargetsLock.unlock()
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = "Bağlantı Yok"
            self.onConnectionStatusChanged?(false)
        }
    }
}
