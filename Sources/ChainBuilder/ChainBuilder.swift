// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: arbitrary)
public macro ChainBuiler() = #externalMacro(module: "ChainBuilderMacros", type: "ChainBuilderMacro")
