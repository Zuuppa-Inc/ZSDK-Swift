// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "zsdk_swift",
    // Enables localization: SwiftPM picks up the `<lang>.lproj` folders under
    // the target and generates the resource bundle's Info.plist localizations.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "zsdk_swift",
            targets: ["zsdk_swift"]
        ),
    ],
    dependencies: [
        // Stripe's iOS SDK powers the card / Apple Pay payment sheet.
        .package(url: "https://github.com/stripe/stripe-ios.git", from: "24.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "zsdk_swift",
            dependencies: [
                .product(name: "StripePaymentSheet", package: "stripe-ios"),
            ],
            resources: [
                // Processes everything under Resources:
                //  • Fonts/  — Material Icons (Apache-2.0 / CC-BY), same glyphs as the app
                //  • Images/ — Zuuppa wordmark + App Store badge
                //  • <lang>.lproj/ — localized strings for the 7 supported languages
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "zsdk_swiftTests",
            dependencies: ["zsdk_swift"]
        ),
    ]
)
