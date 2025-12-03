//
//  ContentView.swift
//  tedee example
//
//  Created by Mateusz Samosij on 21/02/2024.
//

import SwiftUI
import TedeeLock

enum FocusableField: Hashable {
    case command
    case parameters
}

enum ConnectionStatus: String {
    case connected = "Connected"
    case connecting = "Connecting"
    case disconnected = "Disconnected"
    
    var color: Color {
        switch self {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return .red
        }
    }
}

struct ContentView: View {
    @Bindable var viewModel: ContentViewModel
    @State var command = ""
    @State var parameters = ""
    @FocusState var focus: FocusableField?
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Text(viewModel.serialNumber.serialNumber)
                        .font(.largeTitle)
                        .lineLimit(1)
                        .scaledToFill()
                    Spacer()
                }
                
                HStack {
                    Spacer()
                    Text(viewModel.connectionStatus.rawValue)
                        .foregroundStyle(viewModel.connectionStatus.color)
                        .font(.title)
                    Spacer()
                }
            }
            
            Section {
                Toggle("Keep connection?", isOn: $viewModel.keepConnection)
                HStack {
                    Button {
                        Task {
                            await viewModel.connect()
                        }
                    } label: {
                        Text("Connect")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        Task {
                            await viewModel.disconnect()
                        }
                    } label : {
                        Text("Disconnect")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Section {
                HStack {
                    Button {
                        viewModel.pullLock()
                    } label: {
                        Text("Pull")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        viewModel.openLock()
                    } label: {
                        Text("Open")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        viewModel.closeLock()
                    } label: {
                        Text("Close")
                    }
                    .buttonStyle(.bordered)
                }
                HStack {
                    Spacer()
                    Button {
                        viewModel.getLockStatus()
                    } label: {
                        Text("Get lock status")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }

            Section {
                VStack {
                    Text("Persistent Notification")
                        .font(.headline)
                    HStack {
                        Button {
                            Task {
                                try? await NotificationManager.shared.showPersistentNotification()
                            }
                        } label: {
                            Text("Show Notification")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            NotificationManager.shared.removePersistentNotification()
                        } label: {
                            Text("Hide Notification")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Command")
                            TextField("0x00", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focus, equals: .command)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Parameters")
                            TextField("0x00, 0x00, 0x00", text: $parameters)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focus, equals: .parameters)
                        }
                    }
                    Button {
                        focus = nil
                        Task {
                            await viewModel.sendCommand(command, parameters: parameters)
                        }
                    } label: {
                        Text("Send command")
                    }.buttonStyle(.bordered)
                }
            }
            
            Section {
                ForEach(viewModel.comunicationList.reversed()) { item in
                    Text(item.text)
                }
            }
        }
        .onAppear {
            viewModel.configureStreams()
        }
    }
}

#Preview {
    ContentView(viewModel: ContentViewModel())
}
