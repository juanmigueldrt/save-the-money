import Foundation
import STMCore
import Supabase

/// Score crediticio sobre Supabase. El RLS sólo deja ver y tocar los de quien tiene la sesión.
extension SupabaseBackend: CreditScoreService {
    private static let scoreColumns = "id,score,max_score,provider,recorded_on,note"

    public func creditScores() async throws -> [CreditScore] {
        try await mapped {
            try await client.from("credit_scores")
                .select(Self.scoreColumns)
                .order("recorded_on", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
    }

    public func addCreditScore(_ score: CreditScore) async throws -> CreditScore {
        if let issue = score.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("credit_scores")
                .insert(score)
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
