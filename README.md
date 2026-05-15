# iOS LLM Streaming Demo

> Production-ready streaming LLM integration for iOS · Swift Concurrency · SwiftUI · Anthropic-compatible API

A native iOS demo showing token-by-token streaming with an LLM API following the Anthropic Messages API spec (currently powered by DeepSeek as the backend). Built with `URLSession.AsyncBytes` + `AsyncThrowingStream`, with production-grade cancellation, timeout, and error handling.

## Why this exists

Most "Swift + LLM streaming" tutorials online stop at "make the API call work." Real iOS apps need:

- **Cancellation that actually terminates the HTTP connection** — not just the UI loop
- **Sensible timeouts** — `URLSession.shared`'s defaults (60s request, **7 days** resource) are not production-ready
- **Auto-scrolling output** — streaming text that stays out of view is useless to users
- **Typed errors** — distinguish network failure, authentication, rate limits, and decoding failures

This demo addresses all of the above in roughly 200 lines of Swift.

## Features

- ✅ Token-by-token streaming via Server-Sent Events
- ✅ Clean cancellation across `AsyncThrowingStream` and `URLSession`
- ✅ Custom `URLSession` (10s request timeout, fail-fast on no connectivity)
- ✅ Typed error handling (`LLMError` enum for network / auth / rate limit / server / decoding)
- ✅ Auto-scrolling response view (`ScrollViewReader` + invisible anchor pattern)
- ✅ Secure API key management via `.xcconfig` (gitignored)
- ✅ Anthropic Messages API spec — portable across Claude, DeepSeek, and compatible providers

## Tech Stack

- Swift 5.9+
- SwiftUI
- Swift Concurrency (`AsyncThrowingStream`, `Task`, `URLSession.AsyncBytes`)
- iOS 17+
- Xcode 16+

## Architecture

    StreamingDemo/
    ├── App/                          App entry point
    ├── Views/
    │   └── ContentView.swift         UI + state management
    ├── Services/
    │   └── LLMService.swift          HTTP + SSE parsing layer
    └── Config/
        ├── Secrets.example.xcconfig  Template (committed)
        └── Secrets.xcconfig          Real keys (gitignored)

Two clean layers:

- **`LLMService`** — Network I/O, SSE parsing, typed errors. Zero UI knowledge.
- **`ContentView`** — UI state, user interaction, error display. Zero network knowledge.

## Getting Started

### 1. Clone

    git clone git@github.com:leoliao2026/ios-llm-streaming-demo.git
    cd ios-llm-streaming-demo

### 2. Configure your API key

    cp StreamingDemo/Config/Secrets.example.xcconfig StreamingDemo/Config/Secrets.xcconfig

Edit `Secrets.xcconfig` and add your key:

    DEEPSEEK_API_KEY = sk-your-key-here

> Get a DeepSeek key at https://platform.deepseek.com. The Anthropic-compatible endpoint is at `https://api.deepseek.com/anthropic`. To swap to the real Anthropic API, change the base URL in `LLMService.swift` and your `x-api-key` header value.

### 3. Run

Open `StreamingDemo.xcodeproj` in Xcode 16+, select an iOS 17+ simulator, press ⌘R.

## Implementation Notes

### Cancellation propagation

Cancelling the outer `Task` does **not** automatically cancel the inner `AsyncThrowingStream`'s work. We bridge them via `continuation.onTermination`:

    continuation.onTermination = { @Sendable _ in
        task.cancel()
    }

Without this, pressing Cancel would show "✓ Completed" with stale partial output — a silent UX bug that doesn't surface in unit tests.

### Custom URLSession timeouts

`URLSession.shared` defaults to a 60s request timeout and a **7-day** resource timeout. For an LLM streaming client, both are unusable:

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

`timeoutIntervalForRequest` in streaming context means "max gap between chunks", not "max total time" — a common misunderstanding.

### Auto-scroll without clipping

Naively calling `proxy.scrollTo(textID, anchor: .bottom)` clips long content (only the last line stays visible). The fix: place an invisible 1pt anchor *after* the text:

    ScrollViewReader { proxy in
        ScrollView {
            Text(outputText)
            Color.clear.frame(height: 1).id("bottom_anchor")
        }
        .onChange(of: outputText) { _, _ in
            withAnimation { proxy.scrollTo("bottom_anchor", anchor: .bottom) }
        }
    }

### `max_tokens` is a silent killer

The API returns HTTP 200 even when the response is cut off mid-sentence due to `max_tokens` being too small. The dev surface looks like "✓ Completed" but the content stops at `- **Ex`. Future work: surface `stop_reason` in the UI.

## Roadmap

- [ ] Tool Use / Function Calling integration
- [ ] Multi-turn conversation support
- [ ] `stop_reason` display (so users know *why* a response ended)
- [ ] Retry with exponential backoff for 429 / 5xx
- [ ] Dark mode support
- [ ] Apple Foundation Models (`@Generable`) comparison branch

## License

MIT

## About

Built by [Hao Hsiang Liao (Leo)](https://github.com/leoliao2026) — an iOS developer specializing in on-device and cloud-based AI integration. 10+ years of mobile and backend experience across iOS Native, Godot, and Go.