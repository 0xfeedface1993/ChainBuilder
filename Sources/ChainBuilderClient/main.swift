import ChainBuilder

@ChainBuiler
struct User: Equatable {
    var name: String
    private let age: Int
    let qq: String
    var isTest: Double
    private var sex: Bool = false
    private var _code: Int
    var code: Int {
        get {
            _code
        }
        
        set {
            _code = newValue
        }
    }
}

//
//@ChainBuiler
//class UserBan {
//    var name: String
//    let age: Int
//}

let user = User(name: "test", age: 100, qq: "123444", isTest: 0.0, sex: true, code: 2)
let old = user.name("cococo")
print("old user \(old)")
