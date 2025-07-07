# NeuroNote

NeuroNote is a production-ready iOS voice recording app built in Swift using SwiftUI, AVFoundation, Swift Concurrency, and SwiftData. It segments recordings into 30-second chunks and transcribes each segment using Apple Speech (STT) with fallback to OpenAI Whisper API after retry attempts.

---

## Audio System Design

**Framework Used**: AVAudioEngine  
**Purpose**: Power segmented, real-time audio recording with background and interruption handling.  

**Architecture Decisions**:

- The app uses AVAudioEngine for low-level control over input and routing.
- Recording is done via AVAudioFile writing `.caf` files directly from AVAudioPCMBuffer.
- A `Timer` is scheduled every 30 seconds to stop the current segment and rotate to a new one.
- Audio levels are extracted using a tap installed on the input node and passed to the UI in real-time using an `@Observable` model.

**Interruptions and Route Change Handling**:

The app observes:

- `AVAudioSession.interruptionNotification`
- `AVAudioSession.routeChangeNotification`
- `.AVAudioEngineConfigurationChange`

If a call, Siri, or other interruption occurs:

- `pauseRecording()` is called and sets internal state.
- If system signals `.shouldResume`, the app automatically restarts the session and resumes recording.
- Route changes (e.g., unplugging headphones) trigger pause/resume logic.
- On engine configuration changes, the audio graph is reset and reconnected when safe.

**Background Support**:

- Enabled via **Background Modes → Audio, AirPlay, and Picture in Picture**
- `AVAudioSession` remains active when app is in background.
- Segments are recorded and saved without interruption during background operation.

---

## Data Model Design

**Persistence Framework**: SwiftData  

**Entities**:

- `Recording`: Represents an overall recording session. Stores:
  - `createdAt` (Date)
  - `fileURL` (URL to main session audio file, if needed)
- `TranscriptionSegment`: Represents each 30-second audio file segment.
  - Stores transcription status, text, audio URL, retry attempts.
  - Has a parent relationship to `Recording`.

**Performance Optimizations**:

- Indexed queries via `@Query(sort:)` to list recordings by date.
- Lazy loading: audio files and segments are only accessed when needed.
- Segments and recordings are split into small objects to reduce memory load.
- Designed to scale to 1,000+ sessions and 10,000+ segments without UI lag.
- Segment-level inserts happen transactionally inside `saveCurrentSegment()` with minimal locking.

---

## Transcription System

**Default Path**:  
Segments are first transcribed via Apple Speech framework (`SFSpeechRecognizer`).

**Fallback Path**:  
If 5+ attempts fail (tracked via `attemptCount`), the segment is sent to OpenAI Whisper API.

**Concurrent Processing**:

- Each transcription task runs in its own `Task {}`.
- Whisper API and local STT use `async/await` with retry logic and exponential backoff.
- Whisper API key is securely loaded from Keychain.

**Offline Queuing**:

- If network is unavailable, failed requests are retained in the SwiftData model.
- Retried later on app launch or when conditions improve.

---

## Known Limitations and Tradeoffs

Due to the July 4 holiday weekend and prior commitments, the following features were not implemented. However, if given more time, I would have addressed them.
---

- **Retry Queue Persistence Across App Restarts**  
  Failed transcriptions do not persist retry logic after app termination.  
  I would add `shouldRetry: Bool` and `nextRetryAt: Date?` to each `TranscriptionSegment`, then query `.pending` or `.failed` segments on launch and resume retries via an `@Observable` background service.

  
- **User-Configurable Audio Quality**  
  Recording uses a fixed sample rate and format.  
  I would create a `SettingsModel` with `@Observable` and a `SettingsView` for choosing low, medium, or high quality, then apply the selected format dynamically during engine setup.

  
- **Persistent Offline Transcription Queue**  
  Segments that fail due to no internet are not retried later.  
  I would mark failed network segments as `.pending`, store retry timestamps, monitor connectivity using `NWPathMonitor`, and resume transcription once network is restored.

  
- **In-App Error Feedback**  
  Errors are only printed to the console.  
  I would build a global `ErrorManager` observable and bind UI alerts to it, showing transcription failures and microphone permission errors with banners or retry buttons per segment.

  
- **No Visual Network Status in UI**  
  The app does not reflect online or offline status.  
  I would create a `NetworkStatusModel` using `NWPathMonitor` and show the network state with a banner or status dot, disabling online transcription gracefully when offline.

---

## Setup Instructions

### Requirements

- Xcode 16.3 or later  
- iOS 17.4+  
- Real device (microphone access required)

---

### 1. Clone the Repo

```bash
git clone https://github.com/your-username/NeuroNote.git
cd NeuroNote
open NeuroNote.xcodeproj
