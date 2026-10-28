import Foundation

/// Reads a multi-line paste from standard input.
///
/// When stdin is a terminal, canonical input mode limits a single line to
/// 1024 bytes on macOS and silently drops the rest, which truncates the long
/// cookie line of a copied curl command. The terminal is therefore switched
/// to non-canonical mode (no echo) for the duration of the paste, and input
/// ends at an empty line, Ctrl-D, or end of input. Piped input is read to
/// the end.
enum PasteReader {
    static func read() -> String {
        guard isatty(STDIN_FILENO) == 1 else {
            return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        var original = termios()
        tcgetattr(STDIN_FILENO, &original)
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &original)
            print()
        }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        var lastReport = 0
        while true {
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count <= 0 { break }
            var done = false
            for byte in buffer[0..<count] {
                if byte == 0x04 { done = true; break }
                bytes.append(byte)
            }
            if bytes.count - lastReport >= 512 || done {
                lastReport = bytes.count
                print("\r  received \(bytes.count) bytes…", terminator: "")
                fflush(stdout)
            }
            if done { break }
            // An empty line (two consecutive line breaks) ends the paste once
            // something has been pasted.
            if bytes.count >= 2, bytes.suffix(2) == [0x0A, 0x0A] || bytes.suffix(2) == [0x0D, 0x0D],
                !bytes.dropLast(2).allSatisfy({ $0 == 0x0A || $0 == 0x0D || $0 == 0x20 })
            {
                break
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
