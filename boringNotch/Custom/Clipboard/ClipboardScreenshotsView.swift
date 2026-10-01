//
//  ClipboardScreenshotsView.swift
//  boringNotch
//
//  The "Буфер" section: clipboard history on the left, screenshots on the right.
//  Either half can be turned off in Settings → Clipboard & Screenshots.
//

import SwiftUI
import Defaults

struct ClipboardScreenshotsView: View {
    @Default(.showClipboardTab) private var clipboardEnabled
    @Default(.showScreenshotsTab) private var screenshotsEnabled

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if clipboardEnabled {
                ClipboardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            if clipboardEnabled && screenshotsEnabled {
                Divider().opacity(0.3)
            }
            if screenshotsEnabled {
                ScreenshotsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
