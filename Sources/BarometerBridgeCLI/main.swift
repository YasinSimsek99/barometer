import ClaudeCodeBridge
import Foundation

let maximumSize = 2 * 1_048_576
let input = (try? FileHandle.standardInput.read(upToCount: maximumSize + 1)) ?? Data()
guard input.count <= maximumSize else {
    exit(0)
}

let runner = BridgeRunner(maximumInputSize: maximumSize)
runner.capture(input)
exit(runner.runPreviousStatusLine(input: input))
