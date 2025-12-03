//
//  ContentViewModel.swift
//  tedee example
//
//  Created by Mateusz Samosij on 22/02/2024.
//

import Foundation
import TedeeLock

struct ComunicationListItem: Identifiable {
    let id = UUID()
    let text: String
    let date = Date()
    
    init(_ text: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        
        self.text = dateFormatter.string(from: Date()) + " - " + text
    }
}

@Observable
final class ContentViewModel {
    let serialNumber: TedeeSerialNumber
    let certificate: TedeeCertificate
    
    var connectionStatus: ConnectionStatus = .disconnected
    var keepConnection = false
    var comunicationList = [ComunicationListItem]()
    
    init() {
        print("Public key to register in api: \(TedeeLockManager.publicKey)")
        do {
            serialNumber = try TedeeSerialNumber(serialNumber: Configuration.SerialNumber)
            certificate = try TedeeCertificate(certificate: Configuration.Certificate,
                                               expirationDate: Configuration.expirationDate,
                                               devicePublicKey: Configuration.DevicePublicKey,
                                               mobilePublicKey: Configuration.MobilePublicKey)
        } catch {
            fatalError("\(error)")
        }
    }
    
    @MainActor
    func connect() async {
        do {
            try await TedeeLockManager.shared.connect(serialNumber, certificate: certificate, keepConnection: keepConnection)
            connectionStatus = .connected
        } catch {
            comunicationList.append(ComunicationListItem("connection error: \(error)"))
        }
    }
    
    @MainActor
    func disconnect() async {
        do {
            try await TedeeLockManager.shared.disconnect(serialNumber)
            connectionStatus = .disconnected
        } catch {
            comunicationList.append(ComunicationListItem("disconnection error: \(error)"))
        }
    }
    
    @MainActor
    func sendCommand(_ command: String, parameters: String) async {
        Task {
            guard let commandHex = UInt8(command.dropFirst(2), radix: 16) else { return }
            
            let parameters = parameters.split(separator: ", ").compactMap({ UInt8($0.dropFirst(2), radix: 16) })
            
            do {
                comunicationList.append(ComunicationListItem("request: \(command) params: \(parameters)"))
                
                let response = try await TedeeLockManager.shared.sendCommand(serialNumber, command: commandHex, parameters: parameters)
                
                comunicationList.append(ComunicationListItem("response: \(response)"))
            } catch {
                comunicationList.append(ComunicationListItem("send error: \(error)"))
            }
        }
    }
    
    @MainActor
    func getLockStatus() {
        Task {
            do {
                let lockStatus = try await TedeeLockManager.shared.getLockState(serialNumber)
                comunicationList.append(ComunicationListItem("lock state: \(lockStatus.state)"))
            } catch {
                comunicationList.append(ComunicationListItem("error: \(error)"))
            }
        }
    }
    
    @MainActor
    func openLock() {
        Task {
            do {
                let result = try await TedeeLockManager.shared.openLock(serialNumber)
                comunicationList.append(ComunicationListItem("open result: \(result)"))
            } catch {
                comunicationList.append(ComunicationListItem("error: \(error)"))
            }
        }
    }
    
    @MainActor
    func closeLock() {
        Task {
            do {
                let result = try await TedeeLockManager.shared.closeLock(serialNumber)
                comunicationList.append(ComunicationListItem("close result: \(result)"))
            } catch {
                comunicationList.append(ComunicationListItem("error: \(error)"))
            }
        }
    }
    
    @MainActor
    func pullLock() {
        Task {
            do {
                let result = try await TedeeLockManager.shared.pullLock(serialNumber)
                comunicationList.append(ComunicationListItem("pull result: \(result)"))
            } catch {
                comunicationList.append(ComunicationListItem("error: \(error)"))
            }
        }
    }
    
    func configureStreams() {
        Task { @MainActor in
            for await status in TedeeLockManager.shared.connectionStatusStream {
                if self.serialNumber.serialNumber == status.serialNumber.serialNumber {
                    switch status.status {
                    case .connected:
                        connectionStatus = .connected
                    case .connecting:
                        connectionStatus = .connecting
                    case .disconnected:
                        connectionStatus = .disconnected
                    @unknown default:
                        break
                    }
                    let error: String = if let error = status.error {
                        ", \(error)"
                    } else {
                        ""
                    }
                    comunicationList.append(ComunicationListItem("connection stream: \(connectionStatus.rawValue)\(error)"))
                }
            }
        }

        Task { @MainActor in
            for await notification in TedeeLockManager.shared.notificationsStream {
                if self.serialNumber.serialNumber == notification.serialNumber.serialNumber {
                    switch notification.notification {
                    case .lockState(let lockState):
                        comunicationList.append(ComunicationListItem("lock state changed: \(lockState.state)"))
                    case .generic(let array):
                        comunicationList.append(ComunicationListItem("notification: \(array)"))
                    @unknown default:
                        break
                    }
                }
            }
        }
    }

    @MainActor
    func handleNotificationAction(_ actionIdentifier: String) async {
        comunicationList.append(ComunicationListItem("notification action: \(actionIdentifier)"))

        // Auto-connect if not connected
        if connectionStatus != .connected {
            comunicationList.append(ComunicationListItem("auto-connecting to lock..."))
            await connect()

            // Wait for connection to establish
            try? await Task.sleep(for: .seconds(2))

            // Check if connected
            if connectionStatus != .connected {
                comunicationList.append(ComunicationListItem("failed to auto-connect"))
                return
            }
        }

        // Execute action based on identifier
        switch actionIdentifier {
        case NotificationManager.openActionIdentifier:
            comunicationList.append(ComunicationListItem("executing open from notification"))
            await openLock()
        case NotificationManager.closeActionIdentifier:
            comunicationList.append(ComunicationListItem("executing close from notification"))
            await closeLock()
        case NotificationManager.pullSpringActionIdentifier:
            comunicationList.append(ComunicationListItem("executing pull spring from notification"))
            await pullLock()
        default:
            break
        }
    }
}
