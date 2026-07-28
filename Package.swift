// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "zsdk_swift",
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
                // Bundle the Material Icons font (Apache-2.0 / CC-BY) so the SDK
                // renders the exact same glyphs the Zuuppa app uses.
                .process("Resources/Fonts"),
                // Zuuppa wordmark shown on the confirmation screen.
                .process("Resources/Images"),
            ]
        ),

    ]
)
