import SwiftUI

// Swift mirror of NewsScreen.kt - elevated cards with a cropped thumbnail,
// bold 2-line headline, optional 2-line description, and a published date.
struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TitleLeagueSelector(
                            selectedLeague: viewModel.leagueGroup,
                            onLeagueSelected: { viewModel.leagueGroup = $0 }
                        )
                    }
                }
                .toolbarBackground(theme.backgroundBase, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if let message = viewModel.errorMessage {
            EmptyStateView(title: message, systemImage: "wifi.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if viewModel.articles.isEmpty {
            EmptyStateView(title: "No news right now", systemImage: "newspaper")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.articles) { article in
                        NewsCard(article: article)
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundBase)
        }
    }
}

private let publishedFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

private struct NewsCard: View {
    let article: NewsArticle

    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let link = article.link, let url = URL(string: link) {
                Link(destination: url) { cardContent }
            } else {
                cardContent
            }
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = article.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 72, height: 72)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(article.headline)
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                if let description = article.description, !description.isEmpty, description != article.headline {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                Text(formattedPublished)
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var formattedPublished: String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: article.published) {
            return publishedFormatter.string(from: date)
        }
        guard let date = ISO8601DateFormatter().date(from: article.published) else { return "" }
        return publishedFormatter.string(from: date)
    }
}

#Preview {
    NewsView()
}
