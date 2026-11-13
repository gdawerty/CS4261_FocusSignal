import SwiftUI
import UniformTypeIdentifiers

struct SessionCSVShareItem: Transferable {
    let data: Data

    init(csv: String) {
        data = Data(csv.utf8)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
    }
}

struct SessionCSVExportLink: View {
    let title: String
    let filename: String
    let csv: String
    var accessibilityIdentifier: String = "export.csv"

    var body: some View {
        ShareLink(item: SessionCSVShareItem(csv: csv), preview: SharePreview(filename)) {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
