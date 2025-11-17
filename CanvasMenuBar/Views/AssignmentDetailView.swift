import SwiftUI
import AppKit

struct AssignmentDetailView: View {
    let assignment: Assignment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !assignment.metadataBadges.isEmpty {
                badges
            }
            infoSection
            Divider()
            descriptionSection
            Spacer()
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minWidth: 380, minHeight: 360)
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .font(.title3.bold())
                Text(assignment.displayCourse)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = assignment.htmlURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Canvas", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var badges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(assignment.metadataBadges, id: \.self) { badge in
                    Text(badge.uppercased())
                        .font(.caption2.bold())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.18))
                        )
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(label: "Due", value: assignment.dueTimeLabel)
            infoRow(label: "Relative", value: assignment.relativeDueText)
            if let location = assignment.locationLine {
                HStack {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .lineLimit(2)
                    Spacer()
                    Button {
                        copyLocation(location)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy location")
                    if let mapsURL = assignment.mapsURL {
                        Button {
                            openURL(mapsURL)
                        } label: {
                            Image(systemName: "map")
                        }
                        .help("Open in Maps")
                    }
                }
                .font(.caption)
            }
        }
    }

    private var descriptionSection: some View {
        ScrollView {
            if let rich = assignment.richDescription, !rich.characters.isEmpty {
                Text(rich)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else if let description = assignment.description {
                Text(description)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("No additional details provided.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    private func copyLocation(_ location: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(location, forType: .string)
    }
}

#Preview("Assignment Detail") {
    AssignmentDetailView(
        assignment: Assignment(
            id: "preview",
            title: "Packback 8",
            courseName: "ECON 202",
            courseCode: nil,
            dueAt: Date().addingTimeInterval(3600),
            allDayDate: nil,
            isAllDay: false,
            htmlURL: URL(string: "https://example.com"),
            pointsPossible: 10,
            description: "Respond to the weekly prompt with evidence-backed comments.",
            richDescription: try? AttributedString(markdown: "**Weekly Prompt:** Discuss..."),
            location: "ILSQ W204",
            kind: .assignment,
            tags: ["Required"],
            hasSubmittedSubmissions: false,
            submission: nil
        )
    )
    .frame(width: 420)
}
