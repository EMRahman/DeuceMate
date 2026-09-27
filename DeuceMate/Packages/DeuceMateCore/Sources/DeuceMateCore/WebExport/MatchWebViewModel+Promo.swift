// MatchWebViewModel+Promo.swift — the "Tracked with DeuceMate" strip at the TOP
// of every HTML export: where to get the app (App Store) and learn more (the
// marketing site). The recipient is usually an opponent without DeuceMate, so
// both perspectives carry it, and it leads the page so it's the first thing
// they see.
//
// The copy and URLs live here once; the static fallback and the viewer JS both
// paint this block. Like the AI-app links, these are user-clicked navigations —
// the page still loads nothing on open.
import Foundation

extension MatchWebViewModel {

    /// The App Store listing (same link as the README and the marketing site).
    static let appStoreURL = "https://apps.apple.com/app/id6757105622"
    /// The marketing site — `docs/website/`, published by GitHub Pages. This is
    /// also the App Store Marketing URL, so it must not move.
    static let websiteURL = "https://emrahman.github.io/DeuceMate/"

    static let promo = Promo(
        title: "Tracked with DeuceMate",
        blurb: "Point-by-point tennis scoring on Apple Watch, with charts and stats like these on iPhone. "
            + "Free, no ads.",
        appStoreLabel: "Download on the App Store",
        appStoreURL: appStoreURL,
        websiteLabel: "Learn more",
        websiteURL: websiteURL
    )
}
