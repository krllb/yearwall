import Foundation

public extension KeyedDecodingContainer {
    /// Decoding a stored configuration must never fail as a whole.
    ///
    /// A field that is missing, null, or of the wrong shape — an older build,
    /// a hand-edited defaults entry, a truncated blob — falls back to a
    /// default. Losing one setting is recoverable; losing the whole config,
    /// including the install seed, would change every wallpaper the user has.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        guard let value = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return value ?? fallback
    }
}
