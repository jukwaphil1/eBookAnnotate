import SwiftUI

struct ContentView: View {
    @State private var vm = AppViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .checkingDeps, .installingDeps, .connecting, .error:
                ConnectionView(vm: vm)
            case .connected(let docs):
                DocumentListView(vm: vm, documents: docs)
            }
        }
        .frame(minWidth: 480)
    }
}
