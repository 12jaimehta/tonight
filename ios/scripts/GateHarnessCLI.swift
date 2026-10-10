import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: gate-harness <results.json>\n", stderr)
    exit(2)
}

let data: Data
do {
    data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fail(code: "INVALID_INPUT", message: String(describing: error))
}

do {
    let report = try GateHarness.evaluate(data)
    let json = try JSONSerialization.data(withJSONObject: report.dictionary(), options: [.sortedKeys])
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch let error as GateHarnessError {
    fail(code: error.code, message: error.message)
} catch {
    fail(code: "INVALID_INPUT", message: String(describing: error))
}

func fail(code: String, message: String) -> Never {
    let object: [String: Any] = ["error": code, "message": message]
    if let json = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(2)
}
