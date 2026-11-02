import Foundation

/// Scores en memoria: cada persona sólo ve los suyos, como con el RLS del servidor.
extension InMemoryBackend: CreditScoreService {
    public func creditScores() async throws -> [CreditScore] {
        let user = try requireUser()
        return (scoresByUser[user] ?? []).sorted { $0.recordedOn > $1.recordedOn }
    }

    public func addCreditScore(_ score: CreditScore) async throws -> CreditScore {
        let user = try requireUser()
        if let issue = score.issue { throw AppError.invalidInput(issue) }
        let saved = CreditScore(score: score.score, maxScore: score.maxScore, provider: score.trimmedProvider,
                                recordedOn: score.recordedOn, note: score.note)
        scoresByUser[user, default: []].append(saved)
        return saved
    }

    public func deleteCreditScore(_ scoreId: UUID) async throws {
        let user = try requireUser()
        scoresByUser[user]?.removeAll { $0.id == scoreId }
    }
}
