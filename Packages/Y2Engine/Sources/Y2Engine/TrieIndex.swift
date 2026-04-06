// TrieIndex.swift
// Y2Notes
//
// Custom Trie data structure with Levenshtein fuzzy matching and BM25 scoring.
// No external library dependencies — pure algorithmic implementation.
//

import Foundation

// MARK: - Trie Data Structure

/// A memory-efficient prefix-tree for O(m) prefix lookup where m = query length.
/// Each node stores a character, child map, and optional posting list.
public final class TrieNode {
    public var children: [Character: TrieNode] = [:]
    /// IDs of documents whose tokenised text passes through this node.
    public var postings: [UUID] = []
    /// True when this node represents the end of a complete token.
    public var isTerminal: Bool = false
}

/// Trie-backed full-text index supporting:
/// - O(m) exact prefix search
/// - Fuzzy search via bounded Levenshtein automaton
/// - BM25 relevance scoring
public final class TrieIndex {

    // MARK: - BM25 Tuning

    /// BM25 free parameter controlling term-frequency saturation (1.2–2.0 typical).
    private let k1: Double = 1.4
    /// BM25 free parameter controlling field-length normalisation (0.5–0.8 typical).
    private let b: Double = 0.65

    // MARK: - State

    private let root = TrieNode()
    /// Forward index: docID → [token] for length normalisation.
    private var documentTokens: [UUID: [String]] = [:]
    /// Number of indexed documents.
    public private(set) var documentCount: Int = 0
    /// Average document length in tokens.
    private var averageDocumentLength: Double = 0

    // MARK: - Indexing

    /// Index a document by splitting its text into lowercased tokens and inserting each into the Trie.
    public func indexDocument(id: UUID, text: String) {
        let tokens = tokenise(text)
        guard !tokens.isEmpty else { return }

        // Remove old version if re-indexing.
        if documentTokens[id] != nil {
            removeDocument(id: id)
        }

        documentTokens[id] = tokens
        documentCount += 1
        recomputeAverageLength()

        for token in tokens {
            insertToken(token, documentID: id)
        }
    }

    /// Remove a previously indexed document.
    public func removeDocument(id: UUID) {
        guard let tokens = documentTokens.removeValue(forKey: id) else { return }
        documentCount = max(0, documentCount - 1)
        recomputeAverageLength()

        for token in tokens {
            removeToken(token, documentID: id)
        }
    }

    /// Remove all documents and reset the Trie.
    public func clear() {
        root.children.removeAll()
        root.postings.removeAll()
        documentTokens.removeAll()
        documentCount = 0
        averageDocumentLength = 0
    }

    // MARK: - Search

    /// Exact prefix search — returns document IDs containing any token starting with `prefix`.
    public func prefixSearch(_ prefix: String) -> Set<UUID> {
        let key = prefix.lowercased()
        guard let node = findNode(key) else { return [] }
        return collectPostings(from: node)
    }

    /// Fuzzy search — returns document IDs containing tokens within `maxDistance` edits of `query`.
    /// Uses a bounded Levenshtein automaton traversal over the Trie.
    public func fuzzySearch(_ query: String, maxDistance: Int = 1) -> [UUID: Int] {
        let key = query.lowercased()
        var results: [UUID: Int] = [:]  // docID → best edit distance

        // Depth-first traversal with Levenshtein row propagation.
        let initialRow = Array(0...key.count)
        fuzzyDFS(node: root, row: initialRow, query: key, maxDistance: maxDistance, results: &results)
        return results
    }

    /// BM25-scored search combining exact prefix hits and fuzzy matches.
    /// Returns (docID, score) pairs sorted by descending score.
    public func rankedSearch(_ query: String, maxFuzzyDistance: Int = 1) -> [(id: UUID, score: Double)] {
        let queryTokens = tokenise(query)
        guard !queryTokens.isEmpty else { return [] }

        var scoreAccumulator: [UUID: Double] = [:]

        for token in queryTokens {
            // Exact prefix matches get full BM25 weight.
            let exactHits = prefixSearch(token)
            for docID in exactHits {
                let tf = termFrequency(token: token, in: docID)
                let idf = inverseDocumentFrequency(token: token)
                let bm25 = bm25Score(tf: tf, idf: idf, docID: docID)
                scoreAccumulator[docID, default: 0] += bm25
            }

            // Fuzzy matches get discounted BM25 weight.
            if token.count >= 3 {
                let fuzzyHits = fuzzySearch(token, maxDistance: maxFuzzyDistance)
                for (docID, distance) in fuzzyHits where !exactHits.contains(docID) {
                    let discount = 1.0 / Double(1 + distance)
                    let tf = termFrequency(token: token, in: docID)
                    let idf = inverseDocumentFrequency(token: token)
                    let bm25 = bm25Score(tf: tf, idf: idf, docID: docID) * discount
                    scoreAccumulator[docID, default: 0] += bm25
                }
            }
        }

        return scoreAccumulator
            .map { (id: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }
    }

    // MARK: - Trie Internal

    private func insertToken(_ token: String, documentID: UUID) {
        var current = root
        for char in token {
            if current.children[char] == nil {
                current.children[char] = TrieNode()
            }
            current = current.children[char]!
            // Store posting at every prefix node for prefix search.
            if !current.postings.contains(documentID) {
                current.postings.append(documentID)
            }
        }
        current.isTerminal = true
    }

    private func removeToken(_ token: String, documentID: UUID) {
        var current = root
        for char in token {
            guard let next = current.children[char] else { return }
            current = next
            current.postings.removeAll { $0 == documentID }
        }
    }

    private func findNode(_ key: String) -> TrieNode? {
        var current = root
        for char in key {
            guard let next = current.children[char] else { return nil }
            current = next
        }
        return current
    }

    private func collectPostings(from node: TrieNode) -> Set<UUID> {
        // The node's postings already contain all documents passing through this prefix.
        return Set(node.postings)
    }

    // MARK: - Levenshtein Automaton

    /// DFS over Trie nodes, propagating a Levenshtein distance row at each level.
    /// The row represents edit distances between the query prefix and the Trie path so far.
    private func fuzzyDFS(
        node: TrieNode,
        row: [Int],
        query: String,
        maxDistance: Int,
        results: inout [UUID: Int]
    ) {
        let queryChars = Array(query)

        // If this node is terminal and within edit distance, record matches.
        if node.isTerminal {
            let editDistance = row[queryChars.count]
            if editDistance <= maxDistance {
                for docID in node.postings {
                    if let existing = results[docID] {
                        results[docID] = min(existing, editDistance)
                    } else {
                        results[docID] = editDistance
                    }
                }
            }
        }

        for (char, child) in node.children {
            // Compute next Levenshtein row for appending `char`.
            var nextRow = [row[0] + 1]  // deletion from query
            for i in 1...queryChars.count {
                let cost = queryChars[i - 1] == char ? 0 : 1
                let insert = nextRow[i - 1] + 1
                let delete = row[i] + 1
                let replace = row[i - 1] + cost
                nextRow.append(min(insert, delete, replace))
            }

            // Prune branches that can never be within maxDistance.
            if let minInRow = nextRow.min(), minInRow <= maxDistance {
                fuzzyDFS(node: child, row: nextRow, query: query, maxDistance: maxDistance, results: &results)
            }
        }
    }

    // MARK: - BM25 Scoring

    /// Okapi BM25 score for a single query term against a document.
    ///
    /// BM25(q, d) = IDF(q) · (tf · (k1 + 1)) / (tf + k1 · (1 - b + b · |d|/avgdl))
    private func bm25Score(tf: Double, idf: Double, docID: UUID) -> Double {
        let docLength = Double(documentTokens[docID]?.count ?? 1)
        let avgDL = max(averageDocumentLength, 1.0)
        let numerator = tf * (k1 + 1.0)
        let denominator = tf + k1 * (1.0 - b + b * docLength / avgDL)
        return idf * numerator / denominator
    }

    /// Term frequency: how many times `token` appears in document `docID`.
    private func termFrequency(token: String, in docID: UUID) -> Double {
        guard let tokens = documentTokens[docID] else { return 0 }
        let count = tokens.filter { $0.hasPrefix(token) }.count
        return Double(count)
    }

    /// Inverse document frequency using the smoothed IDF variant:
    /// IDF(q) = ln((N - n(q) + 0.5) / (n(q) + 0.5) + 1)
    private func inverseDocumentFrequency(token: String) -> Double {
        let n = Double(prefixSearch(token).count)
        let N = Double(max(documentCount, 1))
        return log((N - n + 0.5) / (n + 0.5) + 1.0)
    }

    // MARK: - Tokenisation

    /// Splits text into lowercased word tokens, stripping punctuation.
    /// Custom implementation avoiding NSLinguisticTagger / NLTokenizer.
    public func tokenise(_ text: String) -> [String] {
        var tokens: [String] = []
        var current: [Character] = []

        for char in text.lowercased() {
            if char.isLetter || char.isNumber {
                current.append(char)
            } else {
                if !current.isEmpty {
                    tokens.append(String(current))
                    current.removeAll()
                }
            }
        }
        if !current.isEmpty {
            tokens.append(String(current))
        }
        return tokens
    }

    // MARK: - Helpers

    private func recomputeAverageLength() {
        guard documentCount > 0 else { averageDocumentLength = 0; return }
        let totalTokens = documentTokens.values.reduce(0) { $0 + $1.count }
        averageDocumentLength = Double(totalTokens) / Double(documentCount)
    }
}

// MARK: - Levenshtein Distance (Standalone)

/// Computes the Levenshtein edit distance between two strings.
/// Delegates to SIMD-optimized C kernel (y2_levenshtein.c) operating on
/// Unicode scalar arrays for O(m·n) time, O(min(m,n)) space.
public enum LevenshteinDistance {
    public static func compute(_ source: String, _ target: String) -> Int {
        let s = Array(source.unicodeScalars.map { $0.value })
        let t = Array(target.unicodeScalars.map { $0.value })
        return Int(y2_levenshtein_distance(s, Int32(s.count), t, Int32(t.count)))
    }

    /// Normalised similarity in [0, 1] where 1 = identical.
    public static func similarity(_ source: String, _ target: String) -> Double {
        let s = Array(source.unicodeScalars.map { $0.value })
        let t = Array(target.unicodeScalars.map { $0.value })
        return y2_levenshtein_similarity(s, Int32(s.count), t, Int32(t.count))
    }
}
