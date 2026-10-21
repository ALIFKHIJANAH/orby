import CoreGraphics
import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

@Suite struct ActivityKindTests {
    @Test(arguments: [
        ("Read", ["file_path": "/a/App.swift"], ActivityKind.read),
        ("Edit", ["file_path": "/a/App.swift"], .edit),
        ("Write", ["file_path": "/a/New.swift"], .edit),
        ("Grep", ["pattern": "TODO"], .search),
        ("Glob", ["pattern": "**/*.swift"], .search),
        ("WebFetch", ["url": "https://example.com/docs"], .web),
        ("WebSearch", ["query": "swift canvas"], .web),
        ("Task", ["description": "Audit the login flow"], .delegate),
        ("TodoWrite", [:], .plan),
        ("Bash", ["command": "swift test --parallel"], .test),
        ("Bash", ["command": "npx tsc --noEmit"], .test),
        ("Bash", ["command": "cargo build --release"], .build),
        ("Bash", ["command": "pnpm install --frozen-lockfile"], .build),
        ("Bash", ["command": "git push origin main"], .git),
        ("Bash", ["command": "git status"], .git),
        ("Bash", ["command": "git checkout -b feat/login"], .git),
        ("Bash", ["command": "rm -rf build"], .delete),
        ("Bash", ["command": "npm run dev"], .run),
    ] as [(String, [String: String], ActivityKind)])
    func classifiesTools(tool: String, input: [String: String], kind: ActivityKind) {
        let json = JSONValue.object(input.mapValues { .string($0) })
        let activity = ToolDescriber.activity(tool: tool, input: json)
        #expect(activity.kind == kind, "\(activity.progressive)")
    }

    @Test func bashDescriptionDrivesTheKind() {
        let a = ToolDescriber.activity(tool: "Bash", input: .object(["command": .string("make"), "description": .string("Run the unit tests")]))
        #expect(a.kind == .test)
    }
}

@Suite struct SVGPathTests {
    @Test func parsesAbsoluteAndRelativeLines() {
        let box = SVGPath.parse("M16 6H8v12h8V6zm4 16H4V2h16v20z").boundingBoxOfPath
        #expect(box == CGRect(x: 4, y: 2, width: 16, height: 20))
    }

    @Test func splitsCompactNumbers() {
        // ".5.5" is two numbers and "-1" starts a new one.
        let box = SVGPath.parse("M0 0l.5.5-1 1L2-1z").boundingBoxOfPath
        #expect(abs(box.minX - -0.5) < 1e-9)
        #expect(abs(box.minY - -1) < 1e-9)
        #expect(abs(box.maxX - 2) < 1e-9)
        #expect(abs(box.maxY - 1.5) < 1e-9)
    }

    @Test func arcsWithPackedFlags() {
        // A half circle of radius 1 from (0,0) to (2,0), flags written as "01" with no separator.
        let box = SVGPath.parse("M0 0a1 1 0 012 0").boundingBoxOfPath
        #expect(abs(box.width - 2) < 1e-6)
        #expect(abs(box.height - 1) < 1e-3)
        #expect(abs(box.minY - -1) < 1e-3)
    }

    @Test func smoothCurvesReflectTheirControlPoint() {
        let path = SVGPath.parse("M0 0C0 1 1 1 1 0S2 -1 2 0")
        let box = path.boundingBoxOfPath
        #expect(box.maxY > 0.5 && box.minY < -0.5)
    }

    @Test func stopsAtGarbageWithoutCrashing() {
        #expect(!SVGPath.parse("M1 1L2 2 x 9 9").isEmpty)
        #expect(SVGPath.parse("").isEmpty)
    }
}
