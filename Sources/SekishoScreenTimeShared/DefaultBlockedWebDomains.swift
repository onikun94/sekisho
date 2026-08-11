import ManagedSettings

enum DefaultBlockedWebDomains {
    static let youtube: Set<WebDomain> = [
        WebDomain(domain: "youtube.com"),
        WebDomain(domain: "www.youtube.com"),
        WebDomain(domain: "m.youtube.com"),
        WebDomain(domain: "music.youtube.com"),
        WebDomain(domain: "youtu.be"),
        WebDomain(domain: "youtube-nocookie.com"),
        WebDomain(domain: "www.youtube-nocookie.com")
    ]
}
