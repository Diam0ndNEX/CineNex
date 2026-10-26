//
//  ChromeVisibility.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import SwiftUI
import UIKit

@Observable
@MainActor
final class SceneBoxChromeVisibility {
    private(set) var isVisible = true
    private(set) var autoHideID: UUID?
    private var isHeld = false
    private var transitionAnimation: Animation? {
        UserDefaults.standard.bool(forKey: "cinenex.reduceMotion") || UIAccessibility.isReduceMotionEnabled
            ? nil : .easeOut(duration: 0.18)
    }

    func screenTapped(shouldAutoHide: Bool) {
        withAnimation(transitionAnimation) { isVisible.toggle() }
        autoHideID = isVisible && shouldAutoHide ? UUID() : nil
    }

    func hide() {
        withAnimation(transitionAnimation) { isVisible = false }
        isHeld = false
        autoHideID = nil
    }

    func holdVisible() {
        isHeld = true
        autoHideID = nil
    }

    func releaseHold(autoHide: Bool) {
        isHeld = false
        autoHideID = autoHide && isVisible ? UUID() : nil
    }

    func reveal(autoHide: Bool) {
        withAnimation(transitionAnimation) { isVisible = true }
        autoHideID = autoHide && !isHeld ? UUID() : nil
    }

    func playbackStarted() {
        guard !isHeld else { return }
        autoHideID = isVisible ? UUID() : nil
    }

    func interacted(autoHide: Bool) {
        guard isVisible, !isHeld else { return }
        autoHideID = autoHide ? UUID() : nil
    }

    func viewDisappeared() {
        isHeld = false
        autoHideID = nil
    }

    func autoHide() async {
        guard autoHideID != nil else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        withAnimation(transitionAnimation) { isVisible = false }
        autoHideID = nil
    }
}
