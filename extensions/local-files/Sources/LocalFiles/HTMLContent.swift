import Foundation
import PeerCore
import Readability
import SwiftSoup

func extractHTML(_ source: String) throws -> String {
    let document = try SwiftSoup.parse(source)
    let embedded = try document.select("script[type=application/ld+json]").map { try $0.html() }
    let address =
        try document.select("link[rel=canonical]").first()?.attr("href")
        ?? document.select("meta[property=og:url]").first()?.attr("content")
    let origin = address.flatMap(URL.init(string:))
    try document.select(
        "script,style,noscript,template,form,iframe,object,embed,input:not([type=checkbox]),textarea,select,button,[contenteditable]:not([contenteditable=false])"
    ).remove()
    guard let body = document.body() else { throw PeerError.invalid("HTML 缺少正文。") }
    // A local path is not a web base URL. Relative targets stay unresolved.
    var content = ""
    let comments = try document.select(
        ".crawler-post,[data-testid=issue-body],.react-issue-comment")
    let messages = try document.select("[data-message-id][data-message-author-role]")
    if !comments.isEmpty() {
        content =
            try document.select("[data-testid=header-state]").outerHtml() + comments.outerHtml()
    } else if !messages.isEmpty() {
        for message in messages {
            let article = Element(Tag("article"), "")
            try article.attr("id", message.attr("data-message-id"))
            try article.appendElement("header").text(message.attr("data-message-author-role"))
            try article.append(message.outerHtml())
            content += try article.outerHtml()
        }
    } else if let note = try document.select("main.notion-frame").first() {
        content = try note.outerHtml()
    } else if let posts = try document.select("main,[role=main]").first(),
        try (origin?.host == "bsky.app" && !posts.select("a[href*=\"/post/\"]").isEmpty())
            || !posts.select("a[href*=\"bsky.app/profile/\"][href*=\"/post/\"]").isEmpty()
    {
        content = try posts.outerHtml()
    } else if let posts = try embeddedPosts(embedded) {
        content = posts
    } else {
        let host = origin?.host
        if (host == "chatgpt.com" && origin?.path.hasPrefix("/share/") == true)
            || (host == "bsky.app" && origin?.path.hasPrefix("/profile/") == true)
            || host == "notion.site"
            || host?.hasSuffix(".notion.site") == true
        {
            throw PeerError.needsAction("HTML 中没有已加载正文，请保存加载后的页面。")
        }
        let articles = try document.select("article,.markdown-body").filter { element in
            !element.parents().contains {
                $0.tagName() == "article" || $0.hasClass("markdown-body")
            }
        }
        if articles.count > 1 {
            content = try articles.map { try $0.outerHtml() }.joined(separator: "\n")
        } else {
            do {
                content = try Readability(html: document.outerHtml()).parse().content
            } catch ReadabilityError.contentTooShort {
                // Short notes remain valid; article length is not a content requirement.
            } catch ReadabilityError.noContent {}
            if content.isEmpty { content = try body.html() }
            if let title = try document.select("h1").first() {
                let headings = try SwiftSoup.parse(content).select("h1,h2,h3,h4,h5,h6")
                let titleText = try title.text()
                if try !headings.contains(where: { try $0.text() == titleText }) {
                    content = try title.outerHtml() + content
                }
            }
        }
    }
    let result = try SwiftSoup.parse(content)
    guard let resultBody = result.body(), try !resultBody.text().isEmpty else {
        throw PeerError.needsAction("HTML 中没有可提取的正文。")
    }
    var targets: Set<String> = []
    for element in try result.select("[href],[src],[poster]") {
        for name in ["href", "src", "poster"] where element.hasAttr(name) {
            targets.insert(try element.attr(name))
        }
    }
    for media in try document.select("video,audio") {
        var urls: [String] = []
        for element in [media] + (try media.select("source,track").array()) {
            for name in ["src", "poster"] where element.hasAttr(name) {
                urls.append(try element.attr(name))
            }
        }
        if urls.contains(where: { !targets.contains($0) }) {
            try resultBody.append(media.outerHtml())
            targets.formUnion(urls)
        }
    }
    return try resultBody.html()
}

private func embeddedPosts(_ sources: [String]) throws -> String? {
    func post(_ value: Any?) throws -> Element? {
        guard let item = value as? [String: Any],
            item["@type"] as? String == "DiscussionForumPosting",
            let address = item["url"] as? String, let url = URL(string: address),
            url.scheme == "https", url.host == "bsky.app",
            url.path.range(of: #"^/profile/[^/]+/post/[^/]+$"#, options: .regularExpression) != nil,
            let text = item["text"] as? String, !text.isEmpty
        else { return nil }
        let article = Element(Tag("article"), "")
        let header = try article.appendElement("header")
        let author = item["author"] as? [String: Any]
        try header.appendElement("a").attr("href", address).text(
            author?["name"] as? String ?? address)
        if let date = item["datePublished"] as? String {
            try header.appendText(" · ")
            try header.appendElement("time").attr("datetime", date).text(date)
        }
        let paragraph = try article.appendElement("p")
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if index > 0 { try paragraph.appendElement("br") }
            try paragraph.appendText(line)
        }
        if let quote = try post(item["sharedContent"]) {
            try article.appendElement("blockquote").appendChild(quote)
        }
        return article
    }
    var seen: Set<String> = []
    var content = ""
    for source in sources {
        guard let value = try? JSONSerialization.jsonObject(with: Data(source.utf8)) else {
            continue
        }
        for item in value as? [Any] ?? [value] {
            let posts = (item as? [String: Any])?["hasPart"] as? [Any] ?? [item]
            for item in posts {
                if let article = try post(item), let link = try article.select("header a").first() {
                    let address = try link.attr("href")
                    if seen.insert(address).inserted { content += try article.outerHtml() }
                }
            }
        }
    }
    return content.isEmpty ? nil : content
}
