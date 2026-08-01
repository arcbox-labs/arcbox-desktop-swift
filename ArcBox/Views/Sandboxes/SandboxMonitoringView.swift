// Disabled until ABXD-133 provides real daemon metrics and freshness semantics.
// Do not expose placeholder charts or a LIVE badge backed by app-session state.
#if false
    import SwiftUI

    /// Metric card matching the ArcBox monitoring dashboard style
    struct MetricCard: View {
        let title: String
        let value: String
        let subtitle: String
        var limit: Int?
        var isLive: Bool = true

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if isLive {
                    StatusBadge(color: AppColors.running, label: "LIVE")
                }

                Text(value)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.text)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .textCase(.uppercase)

                if let limit {
                    Text("LIMIT: \(limit)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            )
        }
    }

    /// Chart placeholder matching the ArcBox monitoring style
    struct MonitoringChart: View {
        let title: String
        let value: String
        let subtitle: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                            .textCase(.uppercase)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(value)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.text)
                            Text(subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .textCase(.uppercase)
                        }
                    }

                    Spacer()

                    StatusBadge(color: AppColors.running, label: "LIVE")
                }

                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<4) { _ in
                            Divider()
                                .overlay(AppColors.borderSubtle)
                            Spacer()
                        }
                        Divider()
                            .overlay(AppColors.borderSubtle)
                    }

                    GeometryReader { geo in
                        Path { path in
                            let y = geo.size.height - 2
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(AppColors.running, lineWidth: 2)

                        Circle()
                            .fill(AppColors.running)
                            .frame(width: AppMetrics.statusDot, height: AppMetrics.statusDot)
                            .position(x: geo.size.width - 4, y: geo.size.height - 2)
                    }
                }
                .frame(height: 120)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            )
        }
    }

    /// Sandbox monitoring dashboard view
    struct SandboxMonitoringView: View {
        let vm: SandboxesViewModel

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        MetricCard(
                            title: "Concurrent Sandboxes",
                            value: "\(vm.concurrentSandboxes)",
                            subtitle: "Concurrent Sandboxes\n(live)",
                            limit: vm.concurrentLimit
                        )
                        MetricCard(
                            title: "Start Rate",
                            value: String(format: "%.3f", vm.startRatePerSecond),
                            subtitle: "Start Rate Per Second\n(5-sec rolling avg)",
                            isLive: false
                        )
                        MetricCard(
                            title: "Peak Concurrent",
                            value: "\(vm.peakConcurrentSandboxes)",
                            subtitle: "Peak Concurrent Sandboxes\n(session max)",
                            limit: vm.concurrentLimit,
                            isLive: false
                        )
                    }

                    MonitoringChart(
                        title: "Concurrent Sandboxes",
                        value: "\(vm.concurrentSandboxes)",
                        subtitle: "Average"
                    )

                    MonitoringChart(
                        title: "Start Rate Per Second",
                        value: String(format: "%.3f", vm.startRatePerSecond),
                        subtitle: "Average"
                    )
                }
                .padding(16)
            }
            .background(AppColors.background)
        }
    }
#endif
