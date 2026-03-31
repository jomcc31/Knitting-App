import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Bundle the live activity extension entry point
@main
struct KnitCounterWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProjectCounterLiveActivityWidget()
    }
}

// Render the project's counter on the lock screen and Dynamic Island
struct ProjectCounterLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProjectCounterActivityAttributes.self) { context in
            LockScreenCounterView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.projectTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("Updated \(context.state.lastUpdated, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(primaryValue(for: context.state))
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                        Text(context.state.mode == .rows ? "rows" : "repeats")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    CounterButtonsRow(context: context)
                }
            } compactLeading: {
                Image(systemName: context.state.mode == .rows ? "number.circle.fill" : "repeat.circle.fill")
            } compactTrailing: {
                Text(primaryValue(for: context.state))
                    .font(.caption2.bold())
            } minimal: {
                Text(primaryValue(for: context.state))
                    .font(.caption2.bold())
            }
        }
    }

    // Render the main value for the current mode
    private func primaryValue(for state: ProjectCounterActivityAttributes.ContentState) -> String {
        switch state.mode {
        case .rows:
            return "\(state.totalRows)"
        case .repeats:
            return "\(state.completedRepeats)"
        }
    }
}

// Main lock screen layout for the live activity
private struct LockScreenCounterView: View {
    let context: ActivityViewContext<ProjectCounterActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.projectTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("Updated \(context.state.lastUpdated, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(primaryValue)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())

                    Text(secondaryValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CounterButtonsRow(context: context)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var primaryValue: String {
        switch context.state.mode {
        case .rows:
            return "\(context.state.totalRows)"
        case .repeats:
            return "\(context.state.completedRepeats)"
        }
    }

    private var secondaryValue: String {
        switch context.state.mode {
        case .rows:
            return "total rows"
        case .repeats:
            return "\(context.state.currentRepeatRow) of \(context.state.rowsPerRepeat)"
        }
    }
}

// Shared control row used across lock screen presentations
private struct CounterButtonsRow: View {
    let context: ActivityViewContext<ProjectCounterActivityAttributes>

    var body: some View {
        HStack(spacing: 8) {
            controlButton(systemName: "minus", action: .decrement)

            HStack(spacing: 8) {
                modeButton(title: "Rows", mode: .rows)
                modeButton(title: "Repeats", mode: .repeats)
            }
            .frame(maxWidth: .infinity)

            controlButton(systemName: "plus", action: .increment)
        }
    }

    private var currentModeIntent: WidgetCounterModeIntent {
        context.state.mode == .rows ? .rows : .repeats
    }

    @ViewBuilder
    private func modeButton(title: String, mode: WidgetCounterModeIntent) -> some View {
        Button(intent: SetProjectCounterModeIntent(
            projectID: context.attributes.projectID,
            mode: mode
        )) {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected(mode) ? Color.blue.opacity(0.35) : Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func controlButton(systemName: String, action: WidgetCounterActionIntent) -> some View {
        Button(intent: AdjustProjectCounterIntent(
            projectID: context.attributes.projectID,
            mode: currentModeIntent,
            action: action
        )) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Color.blue)
                .foregroundStyle(.black)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ mode: WidgetCounterModeIntent) -> Bool {
        switch (context.state.mode, mode) {
        case (.rows, .rows), (.repeats, .repeats):
            return true
        default:
            return false
        }
    }
}
