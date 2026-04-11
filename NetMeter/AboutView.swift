//
//  AboutView.swift
//  NetMeter
//

import AppKit
import SwiftUI

/// 关于页固定文案（无远程仓库时请改成你的 GitHub 地址与署名）
private enum AboutAppMetadata {
    static let author = "Shine"
    static let githubRepoURL = URL(string: "https://github.com/PrintNow/NetMeter")!
}

struct AboutView: View {
    private var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v)（\(b)）"
    }

    /// 优先读包内 `AppIcon.icns`（真图标）；仅回退时才用 Workspace（调试时易变成占位图）
    private static func bundledAppIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                Image(nsImage: Self.bundledAppIcon())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                Spacer(minLength: 0)
            }

            Text("NetMeter")
                .font(.title.weight(.bold))

            VStack(alignment: .leading, spacing: 4) {
                Text("版本")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(versionLine)
                    .font(.body.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("作者")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(AboutAppMetadata.author)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("源码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Link("GitHub 项目", destination: AboutAppMetadata.githubRepoURL)
                    .font(.body)
                Text(AboutAppMetadata.githubRepoURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 320, maxWidth: 440, alignment: .topLeading)
        .padding(24)
    }
}

#Preview {
    AboutView()
}
