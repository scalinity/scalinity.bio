import Foundation

struct PubMedCitation: Codable, Hashable {
    let pmid: String
    let text: String
}

actor PubMedRAGService {
    private let apiKeyProvider: () -> String?
    private let store: EncryptedSQLiteStore?
    private let session: URLSession

    init(apiKeyProvider: @escaping () -> String?, store: EncryptedSQLiteStore? = nil, session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.store = store
        self.session = session
    }

    /// Retrieve top-k PubMed citations (abstract snippets) for a query.
    func retrieve(query: String, topK: Int = 5) async throws -> [PubMedCitation] {
        let pmids = try await searchPMIDs(query: query, retmax: max(topK, 5))
        if pmids.isEmpty { return [] }

        var citations: [PubMedCitation] = []
        citations.reserveCapacity(min(topK, pmids.count))

        for pmid in pmids.prefix(topK) {
            if let cached = try await loadCached(pmid: pmid) {
                citations.append(cached)
                continue
            }
            let text = try await fetchAbstractText(pmids: [pmid])
            let citation = PubMedCitation(pmid: pmid, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            citations.append(citation)
            try await saveCached(citation)
        }
        return citations
    }

    // MARK: - Cache

    private func cacheId(pmid: String) -> String { "pmid:\(pmid)" }

    private func loadCached(pmid: String) async throws -> PubMedCitation? {
        guard let store else { return nil }
        guard let data = try await store.get(type: "pubmed", id: cacheId(pmid: pmid)) else { return nil }
        return try JSONDecoder().decode(PubMedCitation.self, from: data)
    }

    private func saveCached(_ citation: PubMedCitation) async throws {
        guard let store else { return }
        let data = try JSONEncoder().encode(citation)
        try await store.put(type: "pubmed", id: cacheId(pmid: citation.pmid), payload: data)
    }

    // MARK: - Entrez API

    private func searchPMIDs(query: String, retmax: Int) async throws -> [String] {
        var comps = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
        comps.queryItems = [
            .init(name: "db", value: "pubmed"),
            .init(name: "term", value: query),
            .init(name: "retmode", value: "json"),
            .init(name: "retmax", value: String(retmax)),
        ]
        if let key = apiKeyProvider(), !key.isEmpty {
            comps.queryItems?.append(.init(name: "api_key", value: key))
        }

        let (data, resp) = try await session.data(from: comps.url!)
        try Self.assertHTTP(resp)

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let esearch = obj?["esearchresult"] as? [String: Any]
        let ids = esearch?["idlist"] as? [String] ?? []
        return ids
    }

    private func fetchAbstractText(pmids: [String]) async throws -> String {
        let ids = pmids.joined(separator: ",")
        var comps = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi")!
        comps.queryItems = [
            .init(name: "db", value: "pubmed"),
            .init(name: "id", value: ids),
            .init(name: "rettype", value: "abstract"),
            .init(name: "retmode", value: "text"),
        ]
        if let key = apiKeyProvider(), !key.isEmpty {
            comps.queryItems?.append(.init(name: "api_key", value: key))
        }

        let (data, resp) = try await session.data(from: comps.url!)
        try Self.assertHTTP(resp)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func assertHTTP(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw InputValidationError.parseFailed("HTTP \(http.statusCode)")
        }
    }
}


