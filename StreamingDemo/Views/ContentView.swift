//
//  ContentView.swift
//  StreamingDemo
//
//  Created by Sean on 5/14/26.
//

import SwiftUI

// MARK: - Stream State
enum StreamState: Equatable {
    case idle               // ready / waiting
    case streaming          // streaming in progress
    case completed          // finished successfully
    case cancelled          // cancelled by user
    case failed(String)     // failed with error message
    
    var label: String {
        switch self {
        case .idle:        return "Ready"
        case .streaming:   return "Streaming…"
        case .completed:   return "✓ Completed"
        case .cancelled:   return "Cancelled"
        case .failed(let msg): return "⚠️ \(msg)"
        }
    }
    
    var isStreaming: Bool {
        if case .streaming = self { return true }
        return false
    }
}

struct ContentView: View {
    // MARK: - State
    @State private var inputText: String = "Hello, World!"
    @State private var outputText: String = ""
    @State private var state: StreamState = .idle
    @State private var streamTask: Task<Void, Never>? = nil
    private let llm = LLMService()
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            inputSection
            Divider()
            buttonSection
            Divider()
            outputSection
            Divider()
            statusBar
        }
    }
    
    // MARK: - Input Section
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROMPT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            TextEditor(text: $inputText)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )
        }
        .padding()
    }
    
    // MARK: - Button Section
    private var buttonSection: some View {
        HStack(spacing: 12) {
            Button(action: send) {
                Label("Send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isStreaming || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Button(action: cancel) {
                Label("Cancel", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!state.isStreaming)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Output Section
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RESPONSE")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(outputText.isEmpty ? "(No response yet)" : outputText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(outputText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .id("output_text")
                    
                    // Invisible anchor at the bottom for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom_anchor")
                }
                .onChange(of: outputText) { _, _ in
                    // Auto-scroll to bottom as new chunks arrive
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom_anchor", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            Text(state.label)
                .font(.caption)
                .foregroundStyle(statusColor)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        switch state {
        case .idle, .completed: return .secondary
        case .streaming: return .blue
        case .cancelled: return .orange
        case .failed: return .red
        }
    }
    
    // MARK: - Actions
    private func send() {
        outputText = ""
        state = .streaming
        let promptToSend = inputText
        
        streamTask = Task {
            await realStream(prompt: promptToSend)
        }
    }
    
    private func cancel() {
        streamTask?.cancel()
        state = .cancelled
    }
    
    private func realStream(prompt: String) async {
        do {
            for try await chunk in llm.streamMessage(prompt: prompt) {
                // Check cancellation on each chunk
                if Task.isCancelled {
                    state = .cancelled
                    return
                }
                outputText.append(chunk)
            }
            
            // Stream finished naturally — double-check it wasn't cancelled
            if Task.isCancelled {
                state = .cancelled
            } else {
                state = .completed
            }
            
        } catch is CancellationError {
            state = .cancelled
        } catch let error as LLMError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    ContentView()
}
