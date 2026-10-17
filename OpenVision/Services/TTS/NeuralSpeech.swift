// OpenVision - NeuralSpeech.swift
// The neural speech engines (Kokoro on-device; Grok, OpenAI and Hermes cloud) behind one interface.
//
// Apple's system voice (TTSService) is always available and is the fallback. The neural engines
// share a contract — whole replies, sentence-streamed replies, and ambient narration that never
// preempts — so the voice agent asks for "the active neural engine" instead of naming one.

import AVFoundation
import Foundation

@MainActor
protocol NeuralSpeechEngine: AnyObject {
    /// True from the moment speech is requested until the last audio has played out.
    var isSpeaking: Bool { get }
    /// Speak a whole reply, replacing anything playing.
    func speak(_ text: String) async
    /// Watch-loop narration: speak only into silence, never preempt a reply.
    func speakAmbient(_ text: String) async
    /// Open a streamed reply; sentences then arrive via `speakChunk` until `endStreaming`.
    func beginStreaming()
    func speakChunk(_ sentence: String)
    func endStreaming()
    func stop()
}

@MainActor
enum NeuralSpeech {
    /// The selected neural engine if it can speak right now, else nil (→ Apple system voice).
    static func active(_ settings: AppSettings) -> NeuralSpeechEngine? {
        switch settings.ttsEngine {
        case .appleSystem: return nil
        case .kokoro: return KokoroTTSService.shared.isModelReady ? KokoroTTSService.shared : nil
        case .grok: return CloudTTSService.grok.isReady ? CloudTTSService.grok : nil
        case .openAI: return CloudTTSService.openAI.isReady ? CloudTTSService.openAI : nil
        case .hermes: return CloudTTSService.hermes.isReady ? CloudTTSService.hermes : nil
        }
    }

    /// Whether any neural engine is speaking — checked regardless of the current selection, since
    /// the setting can change mid-reply.
    static var isAnySpeaking: Bool {
        KokoroTTSService.shared.isSpeaking || CloudTTSService.grok.isSpeaking || CloudTTSService.openAI.isSpeaking
            || CloudTTSService.hermes.isSpeaking
    }

    static func stopAll() {
        KokoroTTSService.shared.stop()
        CloudTTSService.grok.stop()
        CloudTTSService.openAI.stop()
        CloudTTSService.hermes.stop()
    }
}

// MARK: - Speed

/// The reply speed chosen in Settings. The neural engines play through AVAudioUnitTimePitch, which
/// speeds audio up without raising the pitch; Apple's voice takes a rate on each utterance.
@MainActor
enum SpeechRate {
    static let choices: [Double] = [1, 1.25, 1.5, 2]

    static var multiplier: Float { Float(SettingsManager.shared.settings.speechRate) }

    /// AVSpeechUtterance's rate runs from 0 to 1 with normal speech at 0.5, so 2x is its fastest.
    /// The scale isn't linear in words per minute; this is close enough for 1.25–2x.
    static var appleUtteranceRate: Float {
        min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * multiplier)
    }
}

// MARK: - Kokoro

extension KokoroTTSService: NeuralSpeechEngine {
    private var selectedVoice: String { SettingsManager.shared.settings.kokoroVoice }

    func speak(_ text: String) async { await speak(text, voice: selectedVoice) }
    func speakAmbient(_ text: String) async { await speakAmbient(text, voice: selectedVoice) }
    func speakChunk(_ sentence: String) { speakChunk(sentence, voice: selectedVoice) }
}
