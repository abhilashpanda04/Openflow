// Copyright 2025 Abhilash Panda
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import SwiftUI

enum AppStyle {
    enum Palette {
        static let accent = NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.86, alpha: 1.0)
        static let accentSoft = NSColor(calibratedRed: 0.66, green: 0.82, blue: 0.97, alpha: 1.0)
        static let accentWarm = NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.40, alpha: 1.0)
        static let panelBorder = NSColor.white.withAlphaComponent(0.30)
        static let panelFill = NSColor.white.withAlphaComponent(0.08)
        static let panelGlowTop = NSColor.white.withAlphaComponent(0.18)
        static let panelGlowBottom = NSColor.white.withAlphaComponent(0.04)
        static let hintText = NSColor.secondaryLabelColor
        static let subtleText = NSColor.tertiaryLabelColor
    }

    enum Metrics {
        static let cardCornerRadius: CGFloat = 14
        static let panelCornerRadius: CGFloat = 24
        static let cardPadding: CGFloat = 14
        static let rowLabelWidth: CGFloat = 165
        static let contentWidth: CGFloat = 330
        static let pickerWidth: CGFloat = 280
        static let compactControlWidth: CGFloat = 220
        static let smallFieldWidth: CGFloat = 140
        static let numericFieldWidth: CGFloat = 120
    }

    enum Typography {
        static let title = NSFont.systemFont(ofSize: 24, weight: .semibold)
        static let sectionTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 13)
        static let helper = NSFont.systemFont(ofSize: 11)
        static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    }

    enum SwiftUI {
        static let cardBackground = Color(nsColor: .windowBackgroundColor).opacity(0.88)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let subtleText = Color(nsColor: .tertiaryLabelColor)
        static let accent = Color(nsColor: Palette.accent)
        static let accentWarm = Color(nsColor: Palette.accentWarm)
        static let titleFont = Font.system(size: 24, weight: .semibold)
        static let sectionFont = Font.system(size: 13, weight: .semibold)
        static let bodyFont = Font.system(size: 13)
        static let helperFont = Font.system(size: 11)
        static let monoFont = Font.system(size: 12, weight: .medium, design: .monospaced)
    }
}
