import Testing
@testable import PomoTide

struct SpotifyLinkTests {
    @Test(arguments: [
        ("https://open.spotify.com/playlist/37i9dQZF1DX8NTLI2TtZa6?si=abc123", "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"),
        ("  https://open.spotify.com/intl-de/album/4aawyAB9vmqN3uQ7FjRGTy\n", "spotify:album:4aawyAB9vmqN3uQ7FjRGTy"),
        ("spotify:playlist:37i9dQZF1DX8NTLI2TtZa6", "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6"),
    ])
    func acceptsShareLinksAndURIs(text: String, uri: String) {
        #expect(SpotifyLink.uri(from: text) == uri)
    }

    /// The URI ends up inside an AppleScript string, so anything unexpected is refused.
    @Test(arguments: [
        "",
        "https://example.com/playlist/37i9dQZF1DX8NTLI2TtZa6",
        "https://open.spotify.com/user/someone",
        "spotify:playlist:abc\" & do shell script \"x",
        "spotify:playlist",
    ])
    func rejectsEverythingElse(text: String) {
        #expect(SpotifyLink.uri(from: text) == nil)
    }
}
