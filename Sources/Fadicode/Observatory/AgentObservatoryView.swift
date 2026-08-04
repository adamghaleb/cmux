import SwiftUI

/// Main observatory view that shows all running agents grouped by project.
struct AgentObservatoryView: View {
    @ObservedObject private var service = AgentObservatoryService.shared

    var body: some View {
        ZStack {
            // Dark background matching terminal aesthetic
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()

            if service.agents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statsBar
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        Divider()
                            .padding(.horizontal, 20)

                        // Group by project
                        ForEach(sortedProjectKeys, id: \.self) { projectName in
                            if let agents = service.agentsByProject[projectName] {
                                ProjectGroupView(
                                    projectName: projectName,
                                    agents: agents,
                                    onFocusAgent: focusAgent,
                                    onKillAgent: killAgent
                                )
                                .padding(.horizontal, 20)
                            }
                        }

                        Spacer(minLength: 20)
                    }
                }
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            Text(String(
                localized: "observatory.header",
                defaultValue: "Observatory"
            ))
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 12) {
                statBadge(
                    count: service.stats.activeAgents,
                    label: String(localized: "observatory.stat.active", defaultValue: "active"),
                    color: .green
                )
                statBadge(
                    count: service.stats.waitingForInput,
                    label: String(localized: "observatory.stat.waiting", defaultValue: "waiting"),
                    color: .orange
                )
                statBadge(
                    count: service.stats.idleTerminals,
                    label: String(localized: "observatory.stat.idle", defaultValue: "idle"),
                    color: .secondary
                )
                statBadge(
                    count: service.stats.totalTerminals,
                    label: String(localized: "observatory.stat.total", defaultValue: "total"),
                    color: .primary.opacity(0.6)
                )
            }

            Button(action: { service.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "binoculars")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text(String(
                localized: "observatory.empty.title",
                defaultValue: "No agents detected"
            ))
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.secondary)
            Text(String(
                localized: "observatory.empty.subtitle",
                defaultValue: "Open terminal tabs with AI agents to see them here."
            ))
            .font(.system(size: 12))
            .foregroundColor(.secondary.opacity(0.7))
        }
    }

    // MARK: - Helpers

    private var sortedProjectKeys: [String] {
        let groups = service.agentsByProject
        return groups.keys.sorted { a, b in
            let aHasActive = groups[a]?.contains { $0.state.isActive || $0.state.isWaiting } ?? false
            let bHasActive = groups[b]?.contains { $0.state.isActive || $0.state.isWaiting } ?? false
            if aHasActive != bHasActive { return aHasActive }
            return a < b
        }
    }

    private func focusAgent(_ agent: AgentSnapshot) {
        // Post notification to switch to the agent's workspace and panel
        NotificationCenter.default.post(
            name: .fadicodeObservatoryFocusPanel,
            object: nil,
            userInfo: [
                "workspaceId": agent.workspaceId,
                "panelId": agent.id
            ]
        )
    }

    private func killAgent(_ agent: AgentSnapshot) {
        // Post notification to send SIGINT to the agent's terminal
        NotificationCenter.default.post(
            name: .fadicodeObservatoryKillAgent,
            object: nil,
            userInfo: ["panelId": agent.id]
        )
    }
}
