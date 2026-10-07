import Testing
@testable import TCCore

@Test func versionIsSet() { #expect(!TCVersion.string.isEmpty) }
