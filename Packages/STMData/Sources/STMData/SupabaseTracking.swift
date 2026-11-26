import Foundation
import STMCore
import Supabase

/// Score crediticio sobre Supabase. El RLS sólo deja ver y tocar los de quien tiene la sesión.
extension SupabaseBackend: CreditScoreService {
    private static let scoreColumns = "id,score,max_score,provider,recorded_on,note"

    public func creditScores() async throws -> [CreditScore] {
        try await allRows {
            client.from("credit_scores")
                .select(Self.scoreColumns)
                .order("recorded_on", ascending: false)
                .order("created_at", ascending: false)
                .order("id")
        }
    }

    public func addCreditScore(_ score: CreditScore) async throws -> CreditScore {
        if let issue = score.issue { throw AppError.validation(.creditScore(issue)) }
        return try await mapped {
            try await client.from("credit_scores")
                .insert(NewCreditScoreRow(score: score))
                .select(Self.scoreColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteCreditScore(_ scoreId: UUID) async throws {
        try await mapped {
            try await client.from("credit_scores")
                .delete()
                .eq("id", value: scoreId.uuidString)
                .execute()
        }
    }
}

/// Sólo las columnas que se escriben de un score; el id y el dueño los pone el servidor.
struct NewCreditScoreRow: Encodable, Sendable {
    let score: CreditScore

    private enum CodingKeys: String, CodingKey {
        case score, provider, note
        case maxScore = "max_score"
        case recordedOn = "recorded_on"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(score.score, forKey: .score)
        try c.encode(score.maxScore, forKey: .maxScore)
        try c.encode(score.trimmedProvider, forKey: .provider)
        try c.encode(score.recordedOn, forKey: .recordedOn)
        let cleanNote = score.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try c.encode(cleanNote?.isEmpty == false ? cleanNote : nil, forKey: .note)
    }
}
