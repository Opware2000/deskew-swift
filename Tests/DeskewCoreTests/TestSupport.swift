import Swift

/// `true` en build **debug** (`-Onone`), `false` en release (`-O`).
///
/// Sert à éviter d'exécuter en debug les tests qui lancent le binaire `deskew`
/// en sous-processus (très lents sans optimisation). Ces tests tournent en
/// release et en CI.
func isDebugBuild() -> Bool {
    _isDebugAssertConfiguration()
}
