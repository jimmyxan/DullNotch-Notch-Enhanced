//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    let description: String
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home,
             description: "The main view: media player, calendar and your widgets. Always shown."),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf,
             description: "A temporary tray for files: drag files onto the notch to keep them at hand, share or AirDrop them."),
    TabModel(label: "Mixer", icon: "slider.vertical.3", view: .mixer,
             description: "OpenSoundSource: set the volume of each app separately."),
    TabModel(label: "MacRemote", icon: "macbook.and.iphone", view: .remote,
             description: "Control this Mac from your iPhone on the same Wi-Fi: media, volume, brightness, keyboard and touchpad."),
    TabModel(label: "Convert", icon: "arrow.left.arrow.right", view: .converter,
             description: "Convert images and text documents to another format, entirely on this Mac. Nothing is uploaded.")
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.notchTabs) private var notchTabs
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.filter { $0.view == .home || notchTabs.contains($0.view) }) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
