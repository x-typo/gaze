import CryptoKit
import Foundation

nonisolated enum SAPISIDHash {
    static func authorizationHeader(
        sapisid: String,
        origin: String = "https://www.youtube.com",
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> String {
        let source = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(source.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        return "SAPISIDHASH \(timestamp)_\(hash)"
    }
}
