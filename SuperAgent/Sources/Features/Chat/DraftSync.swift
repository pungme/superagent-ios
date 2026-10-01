import Foundation

/// What is typed in a conversation and not sent, shared with the Mac.
///
/// The words live on this phone (so they are there offline and after the app
/// is closed) and the Mac keeps a copy that its own composer and any other
/// device read and write. Two strings per chat decide who wins when they
/// differ: what is in the field, and what the Mac was last known to hold. If
/// those two match, nothing here is unsent to the Mac, so the Mac's version is
/// taken. If they differ, something was typed here that the Mac has not had
/// yet (mid-sentence, or written offline): it stays, and is sent.
enum DraftSync {
    enum Outcome: Equatable {
        /// Both already say the same thing.
        case agree
        /// Show the Mac's text.
        case take(String)
        /// Keep what is here and send it to the Mac.
        case keepAndPush
    }

    /// A field holding only spaces or newlines is an empty one; the Mac
    /// stores it that way too.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
    }

    static func incoming(_ remote: String, local: String, synced: String) -> Outcome {
        let mine = normalized(local)
        if mine == remote { return .agree }
        if mine == synced { return .take(remote) }
        return .keepAndPush
    }

    private static func syncedKey(_ chatID: String) -> String { "draftSynced:" + chatID }

    /// What the Mac holds for this chat, as far as this phone knows. Empty
    /// for a chat never synced — so a draft from before syncing existed reads
    /// as unsent and is kept.
    static func synced(_ chatID: String) -> String {
        UserDefaults.standard.string(forKey: syncedKey(chatID)) ?? ""
    }

    static func setSynced(_ text: String, chatID: String) {
        if text.isEmpty { UserDefaults.standard.removeObject(forKey: syncedKey(chatID)) }
        else { UserDefaults.standard.set(text, forKey: syncedKey(chatID)) }
    }
}
