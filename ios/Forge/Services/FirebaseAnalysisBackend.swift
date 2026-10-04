import Foundation
#if canImport(FirebaseCore) && canImport(FirebaseStorage) && canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseCore
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

/// Uploads set videos to Firebase Storage; a Cloud Function picks them up, runs pose analysis
/// on Cloud Run and writes the result to Firestore, which this class listens to.
final class FirebaseAnalysisBackend: AnalysisBackend {
    enum BackendError: Error { case noVideo, notSignedIn }

    /// Configures Firebase if a GoogleService-Info.plist is bundled. Returns nil otherwise.
    static func makeIfConfigured() -> FirebaseAnalysisBackend? {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return nil }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        return FirebaseAnalysisBackend()
    }

    private func uid() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        // Anonymous auth keeps onboarding frictionless; link to Sign in with Apple later.
        return try await Auth.auth().signInAnonymously().user.uid
    }

    func upload(set: SetRecord, bodyMassKg: Double?, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let file = set.localVideoURL else { throw BackendError.noVideo }
        let uid = try await uid()

        // Create the Firestore doc first so the app can show the set as "uploading" everywhere.
        let doc = Firestore.firestore().document(StoragePaths.setDocument(uid: uid, sessionId: set.sessionId, setId: set.id))
        try await doc.setData([
            "exerciseId": set.exerciseId,
            "setIndex": set.setIndex,
            "plannedReps": set.plannedReps,
            "loggedWeightKg": set.loggedWeightKg.map { $0 as Any } ?? NSNull(),
            "startedAt": Timestamp(date: set.startedAt),
            "endedAt": Timestamp(date: set.endedAt),
            "clientStatus": "uploading",
        ], merge: true)

        let ref = Storage.storage().reference(withPath: StoragePaths.video(uid: uid, sessionId: set.sessionId, setId: set.id))
        let metadata = StorageMetadata()
        metadata.contentType = "video/quicktime"
        metadata.customMetadata = set.uploadMetadata(bodyMassKg: bodyMassKg)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = ref.putFile(from: file, metadata: metadata)
            task.observe(.progress) { snapshot in
                if let p = snapshot.progress, p.totalUnitCount > 0 {
                    progress(Double(p.completedUnitCount) / Double(p.totalUnitCount))
                }
            }
            task.observe(.success) { _ in cont.resume() }
            task.observe(.failure) { snapshot in cont.resume(throwing: snapshot.error ?? BackendError.noVideo) }
        }
        try await doc.setData(["clientStatus": "uploaded"], merge: true)
    }

    func analysisUpdates(for set: SetRecord) -> AsyncStream<(SetRecord.AnalysisStatus, SetAnalysis?)> {
        AsyncStream { continuation in
            Task {
                guard let uid = try? await self.uid() else { continuation.finish(); return }
                let doc = Firestore.firestore().document(StoragePaths.setDocument(uid: uid, sessionId: set.sessionId, setId: set.id))
                let listener = doc.addSnapshotListener { snapshot, _ in
                    guard let data = snapshot?.data() else { return }
                    let status = SetRecord.AnalysisStatus(serverValue: data["status"] as? String)
                    var analysis: SetAnalysis?
                    if let map = data["analysis"] as? [String: Any],
                       let json = try? JSONSerialization.data(withJSONObject: map.jsonSafe) {
                        analysis = try? JSONDecoder().decode(SetAnalysis.self, from: json)
                    }
                    continuation.yield((status, analysis))
                    if status == .done || status == .failed { continuation.finish() }
                }
                continuation.onTermination = { _ in listener.remove() }
            }
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// Firestore returns Timestamps and NSNull; make the map JSON-serialisable.
    var jsonSafe: [String: Any] {
        mapValues { (value: Any) -> Any in
            switch value {
            case let ts as Timestamp: return ts.dateValue().timeIntervalSince1970
            case let dict as [String: Any]: return dict.jsonSafe
            case let arr as [Any]:
                return arr.map { (item: Any) -> Any in
                    if let dict = item as? [String: Any] { return dict.jsonSafe }
                    return item
                }
            default: return value
            }
        }
    }
}
#endif

extension SetRecord.AnalysisStatus {
    init(serverValue: String?) {
        switch serverValue {
        case "processing": self = .processing
        case "done": self = .done
        case "failed": self = .failed
        default: self = .notStarted
        }
    }
}
