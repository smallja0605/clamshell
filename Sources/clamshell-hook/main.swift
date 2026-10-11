import Foundation
import ClamshellCore

// Usage: clamshell-hook <start|end|prompt|pre|post|notify|permreq|stop>   (hook JSON on stdin)
// Always exits 0: a status display must never be able to break or slow down a Claude Code session.
guard CommandLine.arguments.count > 1, let event = HookEvent(rawValue: CommandLine.arguments[1]) else { exit(0) }
let env = HookEnvironment(
    entrypoint: ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"] ?? "",
    terminal: ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "",
    parentPID: getppid())
HookRunner.run(event: event, input: HookRunner.readStandardInput(), env: env)
exit(0)
