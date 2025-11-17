import SwiftUI
import AppKit

struct AssignmentRowView: View {
    let assignment: Assignment
    let isCompleted: Bool
    let showsTracker: Bool
    let toggleCompletion: (() -> Void)?
    let showDetails: (() -> Void)?

    init(assignment: Assignment, isCompleted: Bool = false, showsTracker: Bool = true, toggleCompletion: (() -> Void)? = nil, showDetails: (() -> Void)? = nil) {
        self.assignment = assignment
        self.isCompleted = isCompleted
        self.showsTracker = showsTracker
        self.toggleCompletion = toggleCompletion
        self.showDetails = showDetails
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsTracker, assignment.kind == .assignment, let toggleCompletion {
                Button(action: toggleCompletion) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isCompleted ? .accentColor : .secondary)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(assignment.title)
                        .font(.headline)
                        .lineLimit(2)
                        .strikethrough(showsTracker && isCompleted, color: .primary)
                        .foregroundColor(showsTracker && isCompleted ? .secondary : .primary)
                    Spacer()
                    if assignment.hasDetails, let showDetails {
                        Button(action: showDetails) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("View details")
                    }
                    if assignment.isSubmitted {
                        Label("Submitted", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .labelStyle(.iconOnly)
                            .foregroundColor(.green)
                    } else if assignment.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .help("Overdue")
                    }
                }

                Text(assignment.displayCourse)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !assignment.metadataBadges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(assignment.metadataBadges, id: \.self) { badge in
                            Text(badge.uppercased())
                                .font(.caption2.bold())
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(
                                    Capsule()
                                        .fill(Color(nsColor: .controlAccentColor).opacity(0.15))
                                )
                        }
                    }
                }

                if let location = assignment.locationLine {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let details = assignment.detailSnippet {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack {
                    Label(assignment.dueTimeLabel, systemImage: "clock")
                        .font(.caption)
                    Spacer()
                    Text(assignment.relativeDueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }
}

struct AssignmentRowView_Previews: PreviewProvider {
    static var previews: some View {
        AssignmentRowView(
            assignment: Assignment(
                id: "1",
                title: "Read Chapter 5 + Reflection",
                courseName: "Biology 101",
                courseCode: nil,
                dueAt: Date().addingTimeInterval(3600),
                allDayDate: nil,
                isAllDay: false,
                htmlURL: nil,
                pointsPossible: 10,
                description: "Read pages 121-142 and prepare two discussion questions.",
                richDescription: nil,
                location: "Online",
                kind: .assignment,
                tags: ["Reading"],
                hasSubmittedSubmissions: false,
                submission: nil
            ),
            isCompleted: false,
            showsTracker: true,
            toggleCompletion: {},
            showDetails: {}
        )
        .frame(width: 320)
        .padding()
    }
}
