import Foundation

// Mirrors backend/src/types.ts's News*Json interfaces.

struct NewsArticle: Codable, Identifiable, Hashable {
    let id: Int
    let headline: String
    let description: String?
    let image: String?
    let link: String?
    let published: String
}

struct NewsResponse: Codable {
    let articles: [NewsArticle]
}
