//
//  FilePath.swift
//  DeskewCore
//
//  Travail dérivé de Deskew (MPL 2.0).
//

/// Opérations de chemin reproduisant `GetFileName`, `GetFileDir`,
/// `EnsureTrailingPathDelimiter`, `ChangeFileExt` et `GetFileExt`.
public enum FilePath {

    /// Équivalent de `GetFileName` (gère `/` et `\`).
    public static func fileName(_ path: String) -> String {
        if let index = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            return String(path[path.index(after: index)...])
        }
        return path
    }

    /// Équivalent de `GetFileDir` (gère `/` et `\`, sans délimiteur final).
    public static func fileDir(_ path: String) -> String {
        if let index = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            return String(path[..<index])
        }
        return ""
    }

    /// Équivalent de `EnsureTrailingPathDelimiter` : n'ajoute rien à une chaîne vide.
    public static func ensureTrailingDelimiter(_ dir: String) -> String {
        guard !dir.isEmpty else { return dir }
        if dir.hasSuffix("/") { return dir }
        return dir + "/"
    }

    /// Équivalent de `ChangeFileExt` : remplace l'extension (avec le point).
    public static func changeFileExt(_ name: String, to newExtension: String) -> String {
        if let dot = name.lastIndex(of: ".") {
            return String(name[..<dot]) + newExtension
        }
        return name + newExtension
    }

    /// Équivalent de `GetFileExt` : extension **sans** le point.
    public static func fileExt(_ path: String) -> String {
        let name = fileName(path)
        if let dot = name.lastIndex(of: ".") {
            let ext = String(name[name.index(after: dot)...])
            return ext
        }
        return ""
    }
}
