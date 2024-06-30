import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `ChainBuiler` macro, which automatic
/// create init method (include all store variable parameters),
/// and create value modifier function for every public variable. For example
///
///     @ChainBuilder
///     public struct User: Equatable {
///         var name: String
///         let age: Int
///     }
///
///  will expand to
///
///     public struct User: Equatable {
///         var name: String
///         let age: Int
///
///         public init(name: String, age: Int) {
///             self.name = name
///             self.age = age
///         }
///
///         public func name(_ value: String) -> Self {
///             Self.init(name: value, age: age)
///         }
///
///         public func age(_ value: Int) -> Self {
///             Self.init(name: name, age: value)
///         }
///     }
public struct ChainBuilderMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        
        guard declaration.as(StructDeclSyntax.self) != nil || declaration.as(ClassDeclSyntax.self) != nil else {
            return []
        }
        
        let publicToken = TokenSyntax.keyword(.public)
        let accessLevel = declaration.modifiers
            .first(where: {
                $0.name.text == publicToken.text ||
                $0.name.text == TokenSyntax.keyword(.internal).text
            })
        
        let chaimMembers = MemberBlockSyntaxState(declaration)
        let initMethod = chaimMembers.initlizationFunction(accessLevel: accessLevel)
        let functions = chaimMembers.functions(accessLevel: accessLevel).map(DeclSyntax.init(_:))
        return [DeclSyntax(initMethod)] + functions
    }
}

@main
struct ChainBuilderPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ChainBuilderMacro.self
    ]
}

package extension VariableDeclSyntax {
    var firstIdentifier: TokenSyntax? {
        bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier
    }
}

package extension VariableDeclSyntax {
    var isPrivate: Bool {
        for modifier in modifiers {
            switch modifier.name.text {
            case TokenSyntax.keyword(.private).text:
                return true
            default:
                continue
            }
        }
        return false
    }
    
    var hasDefaultValue: Bool {
        bindings.first?.initializer != nil
    }
}

extension MemberBlockItemListSyntax {
    var chainMembersState: [VariableDeclSyntaxState] {
        compactMap { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                return nil
            }
            
            guard varDecl.bindings.first?.accessorBlock == nil else {
                return nil
            }
            return VariableDeclSyntaxState(metadata: varDecl)
        }
    }
}

package struct MemberBlockSyntaxState {
    let metadata: DeclGroupSyntax
    let members: [VariableDeclSyntaxState]
    
    init(_ syntax: DeclGroupSyntax) {
        self.metadata = syntax
        self.members = syntax.memberBlock.members.chainMembersState
    }
    
    func initlizationFunction(accessLevel: DeclModifierSyntax?) -> InitializerDeclSyntax {
        let prepareData = members.compactMap(FunctionParameterPreparedData.init(_:))
        let count = prepareData.count
        let parameters = prepareData
            .enumerated()
            .compactMap { (index, member) in
                member.syntax(trailingComma: index < (count - 1) ? .commaToken():nil)
            }
        
        let initModifiers = DeclModifierListSyntax(itemsBuilder: {
            if metadata.as(ClassDeclSyntax.self) != nil {
                DeclModifierSyntax(name: TokenSyntax.keyword(.required))
            }
            
            if let accessLevel {
                accessLevel
            }
        })
        
        let bodyStatements = statements()
        let clause = FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(parameters))
        let signature = FunctionSignatureSyntax(parameterClause: clause)
        return InitializerDeclSyntax(modifiers: initModifiers, signature: signature, bodyBuilder: {
            CodeBlockItemListSyntax(bodyStatements)
        })
    }
    
    func statements() -> [CodeBlockItemSyntax] {
        members.map(\.metadata)
            .compactMap(CodeBlockItemPrepareData.init(metadata:))
            .map(\.syntax)
    }
    
    func functions(accessLevel: DeclModifierSyntax?) -> [FunctionDeclSyntax] {
        let nonPrivateMembers = members.filter({ !$0.isPrivate }).map(\.metadata)
        return nonPrivateMembers
            .indices
            .compactMap { index in
                FunctionConstractData(index: index, members: members.map(\.metadata))
            }
            .compactMap(FunctionPrepareData.init(_:))
            .map {
                $0.syntax(accessLevel: accessLevel)
            }
    }
}

package struct VariableDeclSyntaxState {
    let metadata: VariableDeclSyntax
    let isVar: Bool
    let hasDefaultValue: Bool
    let isPrivate: Bool
    
    init(metadata: VariableDeclSyntax) {
        self.metadata = metadata
        self.isVar = metadata.bindingSpecifier == .keyword(.var)
        self.hasDefaultValue = metadata.bindings.first?.initializer != nil
        self.isPrivate = metadata.isPrivate
    }
}

struct FunctionParameterPreparedData {
    let metadata: VariableDeclSyntax
    let firstName: TokenSyntax
    let type: TypeSyntax
    
    init?(_ state: VariableDeclSyntaxState) {
        self.init(metadata: state.metadata)
    }
    
    init?(metadata: VariableDeclSyntax) {
        guard let identifier = metadata.firstIdentifier else {
            return nil
        }
        guard let type = metadata.bindings.first?.typeAnnotation?.type else {
            return nil
        }
//        guard !metadata.hasDefaultValue else {
//            return nil
//        }
        self.metadata = metadata
        self.firstName = identifier
        self.type = type
    }
    
    func syntax(trailingComma: TokenSyntax?) -> FunctionParameterSyntax {
        FunctionParameterSyntax(firstName: firstName, type: type, trailingComma: trailingComma)
    }
}

struct CodeBlockItemPrepareData {
    let item: CodeBlockItemSyntax.Item
    
    init?(metadata: VariableDeclSyntax) {
        guard let identifier = metadata.firstIdentifier else {
            return nil
        }
        let selfIdentifier = DeclReferenceExprSyntax(baseName: .keyword(.self))
        let lhs = ExprSyntax(MemberAccessExprSyntax(base: selfIdentifier, declName: DeclReferenceExprSyntax(baseName: identifier)))
        let rhs = ExprSyntax(DeclReferenceExprSyntax(baseName: identifier))
        self.item = .expr(
            ExprSyntax(
                InfixOperatorExprSyntax(leftOperand: lhs, operator: AssignmentExprSyntax(), rightOperand: rhs)
            )
        )
    }
    
    var syntax: CodeBlockItemSyntax {
        CodeBlockItemSyntax(item: item)
    }
}

struct FunctionConstractData {
    let index: Int
    let members: [VariableDeclSyntax]
}

struct FunctionPrepareData {
    let identifier: TokenSyntax
    let type: TypeSyntax
    let itemList: CodeBlockItemListSyntax
    
    init?(_ data: FunctionConstractData) {
        let metadata = data.members[data.index]
        
        guard let identifier = metadata.firstIdentifier else {
            return nil
        }
        
        guard let type = metadata.bindings.first?.typeAnnotation?.type else {
            return nil
        }
        
        self.identifier = identifier
        self.type = type
        
        let valueIdentifer = TokenSyntax.identifier("value")
        self.itemList = CodeBlockItemListSyntax {
            let called = MemberAccessExprSyntax(base: DeclReferenceExprSyntax(baseName: .keyword(.Self)), declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`)))
            let arguments = LabeledExprListSyntax(
                data.members
                    .indices
                    .compactMap { index in
                        FunctionStatementPrepareData(index: index, primaryMemberIdentifier: identifier, members: data.members, valueIdentifier: valueIdentifer)
                    }
                    .map(\.syntax)
            )
            FunctionCallExprSyntax(calledExpression: called, leftParen: .leftParenToken(), arguments: arguments, rightParen: .rightParenToken())
        }
    }
    
    func syntax(accessLevel: DeclModifierSyntax?) -> FunctionDeclSyntax {
        let valueIdentifer = TokenSyntax.identifier("value")
        let parameters = FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax {
            FunctionParameterSyntax(firstName: .wildcardToken(), secondName: valueIdentifer, type: type)
        })
        let returnClause = ReturnClauseSyntax(type: IdentifierTypeSyntax(name: .keyword(.Self)))
        let signature = FunctionSignatureSyntax(parameterClause: parameters, returnClause: returnClause)
        let statements = itemList
        let body = CodeBlockSyntax(statements: statements)
        return FunctionDeclSyntax(modifiers: DeclModifierListSyntax {
            if let accessLevel {
                accessLevel
            }
        }, name: identifier, signature: signature, body: body)
    }
}

struct FunctionStatementPrepareData {
    let label: TokenSyntax
    let expressionBaseName: TokenSyntax
    let trailingComma: TokenSyntax?
    
    init?(index: Int, primaryMemberIdentifier: TokenSyntax, members: [VariableDeclSyntax], valueIdentifier: TokenSyntax) {
        guard let itemIdentifier = members[index].firstIdentifier else {
            return nil
        }
        self.label = itemIdentifier
        self.trailingComma = index < members.count - 1 ? .commaToken():nil
        self.expressionBaseName = primaryMemberIdentifier == itemIdentifier ? valueIdentifier:itemIdentifier
    }
    
    var syntax: LabeledExprSyntax {
        LabeledExprSyntax(label: label, colon: .colonToken(), expression: DeclReferenceExprSyntax(baseName: expressionBaseName), trailingComma: trailingComma)
    }
}
