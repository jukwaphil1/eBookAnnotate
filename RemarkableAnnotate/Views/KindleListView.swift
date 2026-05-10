import SwiftUI

struct KindleListView: View {
    @Bindable var vm: AppViewModel
    let books: [KindleBook]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kindle")
                    .font(.headline)
                Spacer()
                Button("Disconnect", action: vm.disconnect)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if let result = vm.lastResult {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result).font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.green.opacity(0.08))
            }

            if case .error(let msg) = vm.state {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(msg).font(.callout).foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.red.opacity(0.06))
            }

            if books.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No highlights found in Kindle clippings.")
                        .foregroundStyle(.secondary)
                    Text("Make sure your Kindle is connected via USB.")
                        .font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                    Button("Try Again") { vm.connect(source: .kindle) }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                List(books) { book in
                    KindleBookRow(
                        book: book,
                        isExtracting: vm.extracting == book.id,
                        hasBeenExtracted: vm.extractedUUIDs.contains(book.id)
                    ) {
                        vm.extractKindle(book: book)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct KindleBookRow: View {
    let book: KindleBook
    let isExtracting: Bool
    let hasBeenExtracted: Bool
    let onExtract: () -> Void

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .foregroundStyle(hasBeenExtracted ? .primary : .secondary)
                    if !book.author.isEmpty {
                        Text(book.author)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } icon: {
                Image(systemName: hasBeenExtracted ? "book.fill" : "book")
                    .foregroundStyle(hasBeenExtracted ? Color.accentColor : Color.secondary)
            }

            Spacer()

            Text("\(book.highlightCount) highlight\(book.highlightCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)

            if isExtracting {
                ProgressView().scaleEffect(0.7)
            } else {
                Button("Extract", action: onExtract)
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
