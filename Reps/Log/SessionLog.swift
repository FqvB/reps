import Foundation
import SwiftData

enum SessionLogError: Error, Equatable {
    case notFinished
}

// Session log writes (F8, Q25).
enum SessionLog {
    // Deletes a finished session with its blocks and shots (cascade), then its clip folder once the save succeeds.
    // An active session belongs to SessionController and is refused.
    static func delete(_ session: PracticeSession, in context: ModelContext, clipFiles: any ClipFileRemoving)
        throws
    {
        guard session.status == .finished else { throw SessionLogError.notFinished }
        let sessionID = session.id
        context.delete(session)
        try context.save()
        clipFiles.removeClips(sessionID: sessionID)
    }
}
