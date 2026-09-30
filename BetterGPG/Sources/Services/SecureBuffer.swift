import Darwin
import Foundation

/// Decrypted bytes held in locked memory and zeroed when released.
///
/// `data` shares this storage without copying, so PDFKit and AppKit read from the
/// same pages that `wipe()` clears. Copies those frameworks make internally, and any
/// `String` built from the bytes, are outside this guarantee.
final class SecureBuffer: @unchecked Sendable {
    let data: Data
    let count: Int
    private let pointer: UnsafeMutableRawPointer?
    private let released: ReleaseFlag
    private var wiped = false

    init(taking source: inout Data) {
        let count = source.count
        self.count = count
        let released = ReleaseFlag()
        self.released = released

        guard count > 0 else {
            data = Data()
            pointer = nil
            source = Data()
            return
        }

        let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        source.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                pointer.copyMemory(from: base, byteCount: count)
            }
        }
        source.resetBytes(in: 0..<count)
        source = Data()
        mlock(pointer, count)

        self.pointer = pointer
        data = Data(bytesNoCopy: pointer, count: count, deallocator: .custom { base, _ in
            memset_s(base, count, 0, count)
            munlock(base, count)
            released.value = true
            base.deallocate()
        })
    }

    func wipe() {
        guard !wiped, let pointer, !released.value else { return }
        wiped = true
        memset_s(pointer, count, 0, count)
    }
}

/// Small buffers are copied inline by `Data`, which frees the original allocation immediately.
private final class ReleaseFlag: @unchecked Sendable {
    var value = false
}
