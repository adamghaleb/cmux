import SwiftUI

/// A project section header with its agent cards in a flow layout.
struct ProjectGroupView: View {
    let projectName: String
    let agents: [AgentSnapshot]
    let onFocusAgent: (AgentSnapshot) -> Void
    let onKillAgent: (AgentSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Project header
            HStack {
                Text(projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))

                Spacer()

                Text("\(agents.count) tab\(agents.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
            }

            // Agent cards in horizontal flow
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 10)],
                spacing: 10
            ) {
                ForEach(agents) { agent in
                    AgentCardView(
                        agent: agent,
                        onFocus: onFocusAgent,
                        onKill: onKillAgent
                    )
                }
            }
        }
    }
}
