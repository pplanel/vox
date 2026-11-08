//
//  CustomVocabulary.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import CryptoKit
import Foundation
import Speech
import os

private let log = Logger(subsystem: "dev.pplanel.vox", category: "CustomVocabulary")

/// Builds a custom language model that teaches the dictation model the wake word, the voice
/// command templates and how the names from Settings → Comandos de voz are pronounced, so
/// pt-BR stops hearing "voz" or "box".
/// Only `DictationTranscriber` accepts custom models (`SpeechTranscriber` doesn't).
enum CustomVocabulary {
    /// Bump when the training data below changes in a way the hash wouldn't catch.
    private static let schemaVersion = 2

    /// English X-SAMPA pronunciations, which `SoundsLike` (pt-BR only) doesn't cover. `"` marks
    /// the stressed vowel; symbols a locale doesn't support are silently dropped (see
    /// `SFCustomLanguageModelData.supportedPhonemes`).
    private static let englishPronunciations: [(grapheme: String, phonemes: [String])] = [
        ("Vox", ["v \"A k s"]),
        ("Claude", ["k l \"O d"]),
        ("Pi", ["p \"aI"]),
    ]

    /// Pronunciations from each entity value's "soa como" (pt only); training phrases from every
    /// value's label and every template filled with those labels, all from Settings → Comandos de voz.
    static func vocabulary(for language: String, config: VoiceCommandConfig) -> (terms: [(grapheme: String, phonemes: [String])], phrases: [String]) {
        let terms: [(grapheme: String, phonemes: [String])]
        switch language {
        case "pt":
            terms = config.entities.flatMap(\.values).compactMap { value in
                let phonemes = SoundsLike.pronunciations(value.soundsLike)
                return phonemes.isEmpty || value.label.isEmpty ? nil : (value.label, phonemes)
            }
        case "en":
            terms = englishPronunciations
        default:
            terms = []
        }
        // The answers to a template's confirmation ("vox sim" was heard as "vox Sin"), each
        // value alone after the wake word ("vox Claude", "vox Pi"), then the templates.
        let replies = language == "pt" ? ["sim", "não", "cancelar"] : []
        var seen: Set<String> = []
        let names = config.entities.flatMap(\.values).map(\.label).filter { !$0.isEmpty && seen.insert($0).inserted }
        return (terms, replies + names + CommandResolver.trainingPhrases(for: config))
    }

    /// Returns a ready-to-use model configuration, compiling it the first time for a given
    /// locale and vocabulary (later calls reuse the files on disk, so it only recompiles when
    /// entities or templates change).
    static func configuration(for locale: Locale, wakeWord: String, config: VoiceCommandConfig) async throws -> SFSpeechLanguageModel.Configuration {
        try await requestAuthorization()

        let wakeWord = wakeWord.trimmingCharacters(in: .whitespaces).capitalized
        let language = locale.language.languageCode?.identifier ?? ""
        let (terms, phrases) = vocabulary(for: language, config: config)

        let fingerprint = "\(schemaVersion)|\(locale.identifier)|\(wakeWord)|\(phrases)|\(terms.map { "\($0.grapheme)=\($0.phonemes)" })"
        let version = SHA256.hash(data: Data(fingerprint.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()

        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "dev.pplanel.vox/CustomLM", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = "\(locale.identifier)-\(version)"
        let configuration = SFSpeechLanguageModel.Configuration(
            languageModel: directory.appending(path: "\(base).lm"),
            vocabulary: directory.appending(path: "\(base).vocab")
        )
        if FileManager.default.fileExists(atPath: configuration.languageModel.path) {
            return configuration
        }

        log.info("Compiling custom language model \(base, privacy: .public)")
        let data = SFCustomLanguageModelData(locale: locale, identifier: "dev.pplanel.vox", version: version)
        for term in terms {
            data.insert(term: .init(grapheme: term.grapheme, phonemes: term.phonemes))
        }
        // The wake word alone and before every command, weighted well above ordinary speech.
        data.insert(phraseCount: .init(phrase: wakeWord, count: 500))
        for phrase in phrases {
            data.insert(phraseCount: .init(phrase: "\(wakeWord) \(phrase)", count: 200))
        }
        // Terms only enter the vocabulary through phrases that use them.
        for term in terms where term.grapheme != wakeWord {
            data.insert(phraseCount: .init(phrase: term.grapheme, count: 100))
        }

        let asset = directory.appending(path: "\(base).bin")
        let start = ContinuousClock.now
        do {
            try await data.export(to: asset)
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, configuration: configuration)
        } catch {
            log.error("Compiling custom language model \(base, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let elapsed = (ContinuousClock.now - start).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
        log.info("Compiled custom language model \(base, privacy: .public) in \(elapsed, privacy: .public)")
        removeStaleFiles(in: directory, keeping: base)
        return configuration
    }

    /// Compiling the model goes through the Speech recognition service, which needs this permission.
    private static func requestAuthorization() async throws {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw VoxSpeechError.speechRecognitionDenied
        }
    }

    /// Drops models from previous vocabularies so edits don't pile up files.
    private static func removeStaleFiles(in directory: URL, keeping base: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !file.lastPathComponent.hasPrefix(base) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
