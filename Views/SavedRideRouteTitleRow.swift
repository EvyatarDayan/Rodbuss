//
//  SavedRideRouteTitleRow.swift
//  Rödbuss
//
//  Origin → destination row (dotted arrow) shared by My Rides cards and Dashboard title.
//

import SwiftUI

struct SavedRideRouteTitleRow: View {
    let ride: SavedRide
    var titleFont: Font = .system(size: 17, weight: .bold)
    /// When true (e.g. My Rides card), origin ···► destination is centered as a block. When false, labels span the full width with arrow in the middle.
    var centerRouteLine: Bool = false

    var body: some View {
        let dest = ride.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if dest.isEmpty {
            Text(ride.originName)
                .font(titleFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        } else if centerRouteLine {
            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 12) {
                    Text(ride.originName)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.trailing)
                    RouteDottedArrowSeparator()
                        .frame(width: 32, height: 11)
                    Text(dest)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(ride.originName)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                RouteDottedArrowSeparator()
                    .frame(width: 32, height: 11)
                Text(dest)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Dotted horizontal shaft and small right-pointing chevron between origin and destination.
struct RouteDottedArrowSeparator: View {
    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let w = geo.size.width
            let headInset = min(8, max(4.5, w * 0.26))
            let jointX = max(0, w - headInset)
            let halfHeight: CGFloat = 3.25

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: jointX, y: midY))
                }
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, dash: [2, 4]))
                Path { p in
                    p.move(to: CGPoint(x: jointX, y: midY - halfHeight))
                    p.addLine(to: CGPoint(x: w, y: midY))
                    p.addLine(to: CGPoint(x: jointX, y: midY + halfHeight))
                    p.closeSubpath()
                }
                .fill(Color.secondary)
            }
        }
    }
}
