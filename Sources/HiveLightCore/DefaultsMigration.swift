import Foundation

/// Rename migration (#133): the bundle-ID change moved the app's
/// UserDefaults domain, silently resetting every setting. Copies the known
/// keys from the legacy domain exactly once — `migratedFlagKey` in the
/// target domain guards re-runs, and is stamped even when there was nothing
/// to copy so the legacy domain is never consulted again. Existing target
/// values always win: a setting the user already changed in the renamed app
/// must never be clobbered by an old value.
public func migrateDefaults(from legacy: UserDefaults,
                            to target: UserDefaults,
                            keys: [String],
                            migratedFlagKey: String) {
    guard !target.bool(forKey: migratedFlagKey) else { return }
    for key in keys where target.object(forKey: key) == nil {
        if let value = legacy.object(forKey: key) {
            target.set(value, forKey: key)
        }
    }
    target.set(true, forKey: migratedFlagKey)
}
