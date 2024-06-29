import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(ChainBuilderMacros)
import ChainBuilderMacros

let testMacros: [String: Macro.Type] = [
    "ChainBuilder": ChainBuilderMacro.self,
]
#endif

final class ChainBuilderTests: XCTestCase {
    func testChainMacro() throws {
        #if canImport(ChainBuilderMacros)
        assertMacroExpansion(
            """
            @ChainBuilder
            public struct User: Equatable {
                var name: String
                let age: Int
            }
            """,
            expandedSource: """
            public struct User: Equatable {
                var name: String
                let age: Int

                public init(name: String, age: Int) {
                    self.name = name
                    self.age = age
                }

                public func name(_ value: String) -> Self {
                    Self.init(name: value, age: age)
                }

                public func age(_ value: Int) -> Self {
                    Self.init(name: name, age: value)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testChainInteralMacro() throws {
        #if canImport(ChainBuilderMacros)
        assertMacroExpansion(
            """
            @ChainBuilder
            struct User: Equatable {
                var name: String
                private let age: Int
                private var sex: Bool
            }
            """,
            expandedSource: """
            struct User: Equatable {
                var name: String
                private let age: Int
                private var sex: Bool

                init(name: String, age: Int, sex: Bool) {
                    self.name = name
                    self.age = age
                    self.sex = sex
                }

                func name(_ value: String) -> Self {
                    Self.init(name: value, age: age, sex: sex)
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
