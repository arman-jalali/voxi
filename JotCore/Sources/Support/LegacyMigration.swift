// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Security

/// One-shot migration from the app's pre-rename identity ("Google Transcribe",
/// bundle id com.google.transcribe). This file is the ONLY place the legacy
/// identifiers may appear — everything a user accumulated (API key, settings,
/// dictionary, History) must survive the rename invisibly.
///
/// macOS permissions (mic, Accessibility) are keyed by bundle id and CANNOT be
/// migrated — onboarding re-collects them on first launch as Jot.
public enum LegacyMigration {
    private static let legacyBundleID = "com.google.transcribe"
    private static let legacyKeychainService = "com.google.transcribe"
    private static let legacyAppSupportFolder = "Google Transcribe"
    private static let migratedFlag = "didMigrateFromGoogleTranscribe"

    // Voxi fork: the second rename, com.ammaar.jot / "Jot" → com.voxi.app / "Voxi".
    private static let jotBundleID = "com.ammaar.jot"
    private static let jotAppSupportFolder = "Jot"
    private static let jotMigratedFlag = "didMigrateFromJot"

    public static func runIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: migratedFlag) {
            migrateAppSupportFolder()
            migrateDefaultsDomain()
            migrateKeychainKey()
            defaults.set(true, forKey: migratedFlag)
            Log.session.info("LegacyMigration: completed (folder, defaults, keychain)")
        }
        if !defaults.bool(forKey: jotMigratedFlag) {
            migrateFromJot()
            defaults.set(true, forKey: jotMigratedFlag)
        }
    }

    /// Jot → Voxi. The Voxi folder may already exist (the local model server
    /// lives there), so items move individually instead of the folder wholesale.
    private static func migrateFromJot() {
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = base.appendingPathComponent(jotAppSupportFolder, isDirectory: true)
            let new = FileLayout.appSupportRoot
            if fm.fileExists(atPath: old.path) {
                try? fm.createDirectory(at: new, withIntermediateDirectories: true)
                var moved = 0
                for name in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] {
                    let src = old.appendingPathComponent(name), dst = new.appendingPathComponent(name)
                    guard !fm.fileExists(atPath: dst.path) else { continue }
                    if (try? fm.moveItem(at: src, to: dst)) != nil { moved += 1 }
                }
                if ((try? fm.contentsOfDirectory(atPath: old.path)) ?? []).isEmpty { try? fm.removeItem(at: old) }
                Log.session.info("LegacyMigration: moved \(moved) item(s) from Jot to Voxi")
            }
        }
        // Settings + dictionary from the Jot defaults domain (only keys not yet set).
        if let old = UserDefaults(suiteName: jotBundleID) {
            let defaults = UserDefaults.standard
            var moved = 0
            for (key, value) in old.dictionaryRepresentation() where defaults.object(forKey: key) == nil {
                guard !key.hasPrefix("Apple") && !key.hasPrefix("NS") && !key.hasPrefix("com.apple") else { continue }
                defaults.set(value, forKey: key); moved += 1
            }
            if moved > 0 { Log.session.info("LegacyMigration: moved \(moved) defaults key(s) from Jot") }
        }
    }

    /// recordings/ + history.sqlite move wholesale; FileLayout resolves the NEW
    /// folder name, so this must run before anything touches the store.
    private static func migrateAppSupportFolder() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let old = base.appendingPathComponent(legacyAppSupportFolder, isDirectory: true)
        let new = FileLayout.appSupportRoot
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            Log.session.info("LegacyMigration: moved Application Support folder")
        } catch {
            Log.session.error("LegacyMigration: folder move failed: \(error)")
        }
    }

    /// Settings + dictionary lived in the old bundle id's defaults domain.
    private static func migrateDefaultsDomain() {
        let keys = [
            "smartFormatting", "doubleTapLock", "showIdleIndicator", "soundsEnabled",
            "hotkeyKey", "endpointOverride", "transcribeModelOverride", "cleanupModelOverride",
            "audioRetentionDays", "gateTrips", "dictionaryEntries", "hasCompletedOnboarding",
            "experimentalNoiseHandling", "smartTranscription", "smartCleanupPass",
            "legacyTranscribeEndpoint", "shouldAnnounceSmartRestored",
        ]
        guard let old = UserDefaults(suiteName: legacyBundleID) else { return }
        let defaults = UserDefaults.standard
        var moved = 0
        for key in keys {
            if defaults.object(forKey: key) == nil, let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
                moved += 1
            }
        }
        // No traces: drop the old domain entirely.
        defaults.removePersistentDomain(forName: legacyBundleID)
        if moved > 0 {
            Log.session.info("LegacyMigration: moved \(moved) defaults key(s)")
        }
    }

    /// The Gemini key re-homes to the new Keychain service; the old item is
    /// removed so nothing is left behind.
    private static func migrateKeychainKey() {
        guard KeychainStore.loadAPIKey() == nil, let legacy = readLegacyKey() else { return }
        if KeychainStore.saveAPIKey(legacy) {
            deleteLegacyKey()
            Log.permissions.info("LegacyMigration: API key re-homed to the new Keychain service")
        }
    }

    private static func readLegacyKey() -> String? {
        for dataProtection in [true, false] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyKeychainService,
                kSecAttrAccount as String: "gemini-api-key",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if dataProtection {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    private static func deleteLegacyKey() {
        for dataProtection in [true, false] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyKeychainService,
                kSecAttrAccount as String: "gemini-api-key",
            ]
            if dataProtection {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            SecItemDelete(query as CFDictionary)
        }
    }
}
