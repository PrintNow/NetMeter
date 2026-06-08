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
                .frame(width: 84, height: 84)
                .padding(.bottom, 14)

            Text(NetMeterDisplayName.resolved)
                .font(.title.weight(.bold))
                .padding(.bottom, 5)

            Text(versionLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Divider()
                .padding(.horizontal, 32)
                .padding(.vertical, 18)

            VStack(spacing: 6) {
                Text("© 2026 \(AboutAppMetadata.author)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link("MIT License", destination: AboutAppMetadata.licenseURL)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                Link("GitHub", destination: AboutAppMetadata.repoURL)
                    .font(.footnote)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 28)
        .frame(width: 280)
    }
}

#Preview {
    AboutView()
}
