import Foundation
import PeerCore

// This program links only the library product. It does not open a connection or Keychain UI.
let database = PeerDatabase(applicationVersion: "consumer-example", name: "Independent consumer")
let target = ConnectionTarget(host: "localhost", database: "inkcre", username: "inkcre_core")
try target.validate()
await database.shutdown()
print("PeerCore consumer initialized and closed without App or UI startup")
