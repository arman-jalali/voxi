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

/// The single source of truth for every network deadline in the app.
/// (Critic reconciliation #9 — no other file may define timeout constants.)
public enum TimeoutPolicy {
    /// TCP+TLS connect budget before the attempt is abandoned.
    public static let connect: TimeInterval = 5
    /// Time to the first SSE byte after the request body is sent.
    public static let timeToFirstByte: TimeInterval = 10
    /// Max gap between SSE chunks once streaming has begun.
    public static let interChunkStall: TimeInterval = 10
    /// When the HUD flips to the "Still working…" slow state.
    public static let slowStateUI: TimeInterval = 3

    /// Overall per-request deadline.
    ///
    /// Local Voxtral decodes at roughly 2.5x realtime on Apple Silicon, and long
    /// audio is transcribed in ~20s segments, so cost is linear in duration. The
    /// old cloud formula (30 + duration/4) crossed under the real decode time at
    /// about 3.7 minutes, silently failing dictations well short of the app's own
    /// 10-minute recording cap. Budget generously — a deadline that fires on a
    /// good transcript costs the user their words.
    /// 5s clip → 35s; 10min clip → 10.5min.
    public static func overallDeadline(audioDuration: TimeInterval) -> TimeInterval {
        30 + audioDuration
    }
}
