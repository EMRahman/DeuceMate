import SwiftUI
import DeuceMateCore

/// Shared stats body, with no live match or persistence dependency.
struct MatchStatsContent: View {
    let stats: [PointStat]
    let matchType: MatchType
    var setElapsedSeconds: [Int: TimeInterval] = [:]
    @Environment(\.appTheme) private var theme
    private var meColor: Color { theme.colors.me }
    private var oppColor: Color { theme.colors.opponent }
    private var focalLabel: String { matchType == .doubles ? "Our" : "Me" }
    private var opponentLabel: String { "Opp" }
    var body: some View { tvStatRows }

    // MARK: - TV-style comparison primitives

    @ViewBuilder
    private func splitBar(
        meFrac: Double, oppFrac: Double,
        meLabel: String? = nil, oppLabel: String? = nil
    ) -> some View {
        GeometryReader { geo in
            let halfW = max(0, (geo.size.width - 1) / 2)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(meColor.opacity(0.15))
                    .frame(width: halfW)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(meColor)
                            .frame(width: halfW * meFrac)
                    }
                    .overlay { barLabel(meLabel) }
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)
                Rectangle()
                    .fill(oppColor.opacity(0.15))
                    .frame(width: halfW)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(oppColor)
                            .frame(width: halfW * oppFrac)
                    }
                    .overlay { barLabel(oppLabel) }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// Raw count (e.g. "12/15") centered inside a bar half. `.primary` keeps it
    /// legible over both the pale track and the saturated fill.
    @ViewBuilder
    private func barLabel(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private func comparisonRow(
        _ label: String,
        subtitle: String? = nil,
        meNum: Int, meDen: Int,
        oppNum: Int, oppDen: Int
    ) -> some View {
        let me  = RatioDisplay(numerator: meNum,  denominator: meDen)
        let opp = RatioDisplay(numerator: oppNum, denominator: oppDen)
        let meFrac  = me.fraction
        let oppFrac = opp.fraction
        let meText  = me.percentText
        let oppText = opp.percentText
        let meLabel  = me.countText
        let oppLabel = opp.countText

        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 2) {
                Text(meText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(meColor)
                    .frame(width: 26, alignment: .trailing)
                splitBar(meFrac: meFrac, oppFrac: oppFrac, meLabel: meLabel, oppLabel: oppLabel)
                Text(oppText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(oppColor)
                    .frame(width: 26, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func countComparisonRow(_ label: String, meCount: Int, oppCount: Int) -> some View {
        let maxVal  = max(meCount, oppCount, 1)
        let meFrac  = Double(meCount)  / Double(maxVal)
        let oppFrac = Double(oppCount) / Double(maxVal)

        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 2) {
                Text("\(meCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(meColor)
                    .frame(width: 26, alignment: .trailing)
                splitBar(meFrac: meFrac, oppFrac: oppFrac)
                Text("\(oppCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(oppColor)
                    .frame(width: 26, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). \(focalLabel): \(meCount). \(opponentLabel): \(oppCount).")
        .accessibilityIdentifier("countStat-\(label)")
        .id("countStat-\(label)")
    }

    @ViewBuilder
    private func comparisonSectionHeader(_ title: String) -> some View {
        HStack {
            Text(focalLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(meColor)
            Spacer()
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(opponentLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(oppColor)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func tvPointsWonHeader(me meSummary: MatchStatsSummary) -> some View {
        let total = meSummary.totalPoints
        let meWon = meSummary.pointsWon
        let oppWon = total - meWon
        if total > 0 {
            VStack(spacing: 4) {
                HStack {
                    Text(focalLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(meColor)
                    Spacer()
                    Text("Points Won")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Opp")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(oppColor)
                }
                GeometryReader { geo in
                    let spacing: CGFloat = 2
                    let available = max(0, geo.size.width - spacing)
                    let meFrac = Double(meWon) / Double(total)
                    HStack(spacing: spacing) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(meColor)
                            .frame(width: available * meFrac)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(oppColor)
                            .frame(width: available * (1 - meFrac))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("\(meWon) pts")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(meColor)
                    Spacer()
                    Text("\(total) total")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(oppWon) pts")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(oppColor)
                }
            }
            .padding(.vertical, 3)
            Divider().padding(.vertical, 2)
        }
    }

    // MARK: - TV stat rows (side-by-side comparison)

    @ViewBuilder
    private var tvStatRows: some View {
        let me  = MatchStatsSummary(stats: stats, focal: .me,       setElapsedSeconds: setElapsedSeconds)
        let opp = MatchStatsSummary(stats: stats, focal: .opponent, setElapsedSeconds: setElapsedSeconds)
        let hasAnyOutcomeData = me.totalPoints > me.uncategorizedCount

        VStack(spacing: 2) {
            tvPointsWonHeader(me: me)

            if hasAnyOutcomeData {
                comparisonSectionHeader("Outcome Breakdown")
                HStack(spacing: 2) {
                    Text(me.wueRatio.formatted)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(meColor)
                        .frame(minWidth: 26, alignment: .trailing)
                    VStack(spacing: 0) {
                        Text("Win:Unforced Err")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("aim for > 1.0")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text(opp.wueRatio.formatted)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(oppColor)
                        .frame(minWidth: 26, alignment: .leading)
                }
                .padding(.vertical, 3)
                countComparisonRow("Winners",
                    meCount: me.myWinners,       oppCount: opp.myWinners)
                Text("Errors").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                countComparisonRow("Unforced Errors",
                    meCount: me.myUnforcedErrors, oppCount: opp.myUnforcedErrors)
                countComparisonRow("Forced Errors",
                    meCount: me.myForcedErrors,   oppCount: opp.myForcedErrors)
                countComparisonRow("Double Faults",
                    meCount: me.myDoubleFaults,   oppCount: opp.myDoubleFaults)
                comparisonRow("Aggression Index",
                    subtitle: "W ÷ (W + UE)",
                    meNum: me.myWinners,
                           meDen: me.myWinners + me.myUnforcedErrors,
                    oppNum: opp.myWinners,
                           oppDen: opp.myWinners + opp.myUnforcedErrors)
                comparisonRow("Own Errors %",
                    meNum: me.myDoubleFaults + me.myUnforcedErrors,
                           meDen: me.lostPoints,
                    oppNum: opp.myDoubleFaults + opp.myUnforcedErrors,
                           oppDen: opp.lostPoints)
                if me.uncategorizedCount > 0 {
                    Text("(\(me.uncategorizedCount) uncategorized)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text("Outcome Breakdown")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                Text("Outcome tracking not collected for this match.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }

            Divider().padding(.vertical, 2)

            comparisonSectionHeader("Serve")
            comparisonRow("1st Serve In",
                meNum: me.firstServeIn,    meDen: me.firstServeTotal,
                oppNum: opp.firstServeIn,  oppDen: opp.firstServeTotal)
            comparisonRow("2nd Serve In",
                meNum: me.secondServeIn,    meDen: me.secondServeTotal,
                oppNum: opp.secondServeIn,  oppDen: opp.secondServeTotal)
            comparisonRow("1st Serve Win",
                meNum: me.firstServeWins,   meDen: me.firstServeIn,
                oppNum: opp.firstServeWins, oppDen: opp.firstServeIn)
            comparisonRow("2nd Serve Win",
                meNum: me.secondServeWins,   meDen: me.secondServeIn,
                oppNum: opp.secondServeWins, oppDen: opp.secondServeIn)
            comparisonRow("DF Rate (2nd)",
                meNum: me.doubleFaults,    meDen: me.secondServeTotal,
                oppNum: opp.doubleFaults,  oppDen: opp.secondServeTotal)

            Divider().padding(.vertical, 2)

            comparisonSectionHeader("Return")
            comparisonRow("vs 1st Serve",
                meNum: me.returnWinsOnFirst,    meDen: me.returnOppsOnFirst,
                oppNum: opp.returnWinsOnFirst,  oppDen: opp.returnOppsOnFirst)
            comparisonRow("vs 2nd Serve",
                meNum: me.returnWinsOnSecond,   meDen: me.returnOppsOnSecond,
                oppNum: opp.returnWinsOnSecond, oppDen: opp.returnOppsOnSecond)

            Divider().padding(.vertical, 2)

            comparisonSectionHeader("Break Points")
            comparisonRow("BPs Won (Returner)",
                meNum: me.breakPointWins,   meDen: me.breakPointOpps,
                oppNum: opp.breakPointWins, oppDen: opp.breakPointOpps)
            comparisonRow("BPs Saved (Server)",
                meNum: me.breakPointsFaced - me.breakPointsLost,   meDen: me.breakPointsFaced,
                oppNum: opp.breakPointsFaced - opp.breakPointsLost, oppDen: opp.breakPointsFaced)

            if me.bigPointTotal > 0 && me.normalPointTotal > 0 {
                Divider().padding(.vertical, 2)
                comparisonSectionHeader("Pressure vs Normal")
                comparisonRow("Big Points",
                    meNum: me.bigPointWins,    meDen: me.bigPointTotal,
                    oppNum: opp.bigPointWins,  oppDen: opp.bigPointTotal)
                comparisonRow("Normal Points",
                    meNum: me.normalPointWins,   meDen: me.normalPointTotal,
                    oppNum: opp.normalPointWins, oppDen: opp.normalPointTotal)
            }

            if !me.rallyDepth.isEmpty {
                Divider().padding(.vertical, 2)
                comparisonSectionHeader("Rally Depth Won")
                ForEach(me.rallyDepth, id: \.shot) { meRd in
                    let oppRd = opp.rallyDepth.first { $0.shot == meRd.shot }
                    comparisonRow("@ \(meRd.shot.displayLabel)",
                        meNum: meRd.wins,         meDen: meRd.total,
                        oppNum: oppRd?.wins ?? 0, oppDen: oppRd?.total ?? 0)
                }
            }

            if !me.scoreStates.isEmpty {
                Divider().padding(.vertical, 2)
                comparisonSectionHeader("Score States")
                ForEach(me.scoreStates, id: \.label) { meSs in
                    let oppSs = opp.scoreStates.first { $0.label == meSs.label }
                    comparisonRow(meSs.label,
                        meNum: meSs.wins,         meDen: meSs.total,
                        oppNum: oppSs?.wins ?? 0, oppDen: oppSs?.total ?? 0)
                }
            }

        }
    }
}
