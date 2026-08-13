import SwiftUI

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("News")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("League", selection: $viewModel.leagueGroup) {
                            ForEach(LeagueGroup.allCases) { league in
                                Text(league.rawValue.uppercased()).tag(league)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .task { await viewModel.load() }
                .onChange(of: viewModel.leagueGroup) { _ in
                    Task { await viewModel.load() }
                }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.articles.isEmpty {
            ProgressView()
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
        } else if viewModel.articles.isEmpty {
            EmptyStateView(title: "No news right now", systemImage: "newspaper")
        } else {
            List(viewModel.articles) { article in
                NewsRow(article: article)
            }
            .listStyle(.plain)
        }
    }
}

private struct NewsRow: View {
    let article: NewsArticle

    var body: some View {
        Group {
            if let link = article.link, let url = URL(string: link) {
                Link(destination: url) { rowContent }
            } else {
                rowContent
            }
        }
        .padding(.vertical, 4)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = article.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 88, height: 66)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(article.headline)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if let description = article.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

#Preview {
    NewsView()
}
