//
//  AboutView.swift
//  NetMeter
//

import AppKit
import SwiftUI

private enum AboutAppMetadata {
    static let author = "Shine"
    static let repoURL = URL(string: "https://github.com/PrintNow/NetMeter")!
    static let licenseURL = URL(string: "https://github.com/PrintNow/NetMeter/blob/main/LICENSE")!
}

struct AboutView: View {
    private var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return "\(v) (\(GitInfo.commitHash))"
    }

    private static func bundledAppIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: Self.bundledAppIcon())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .padding(.bottom, 12)

            Text(NetMeterDisplayName.resolved)
                .font(.title2.weight(.semibold))
                .padding(.bottom, 4)

            Text(versionLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Divider()
                .padding(.horizontal, 32)
                .padding(.vertical, 16)

            VStack(spacing: 5) {
                Text("© 2026 \(AboutAppMetadata.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("MIT License", destination: AboutAppMetadata.licenseURL)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Link("GitHub", destination: AboutAppMetadata.repoURL)
                    .font(.caption)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 28)
        .frame(width: 280)
    }
}

#Preview {
    AboutView()
}
