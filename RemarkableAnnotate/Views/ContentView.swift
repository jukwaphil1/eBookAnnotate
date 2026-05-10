import SwiftUI

struct ContentView: View {
    @State private var vm = AppViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .checkingDeps, .installingDeps, .connecting, .error:
                ConnectionView(vm: vm)
            case .connectedRemarkable(let nodes):
                DocumentListView(vm: vm, nodes: nodes)
            case .connectedKindle(let books):
                KindleListView(vm: vm, books: books)
            }
        }
        .frame(minWidth: 480)
    }
}
