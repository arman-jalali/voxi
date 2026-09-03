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

/// Every outbound link in one place, so the About panel, the Settings pane and
/// the docs can never drift apart.
enum JotLinks {
    /// Voxi's own repository. nil hides the Source / Report-a-bug links in About
    /// rather than pointing bug reports at the upstream project.
    static let repository: URL? = nil
    static var issues: URL? { repository?.appendingPathComponent("issues") }
    static var privacy: URL? { repository?.appendingPathComponent("blob/main/docs/PRIVACY.md") }

    /// Upstream: Jot by Ammaar Reshi, which Voxi is a fork of.
    static let upstreamAuthor = URL(string: "https://x.com/ammaar")!
    static let upstream = URL(string: "https://github.com/google-gemini/jot-gemini-transcribe-macOS")!
    /// The model Voxi runs.
    static let model = URL(string: "https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602")!
}
