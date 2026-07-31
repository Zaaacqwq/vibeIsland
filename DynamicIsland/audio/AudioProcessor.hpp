/*
 * VibeIsland (DynamicIsland)
 * Original work Copyright (C) 2026 ZephyrCodesStuff (https://github.com/ZephyrCodesStuff/rtaudio)
 * Modified work Copyright (C) 2026 VibeIsland Contributors
 *
 * Real-time audio processor using Accelerate framework for efficient RMS
 * and biquad filtering.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef AUDIOPROCESSOR_HPP
#define AUDIOPROCESSOR_HPP

#include <Accelerate/Accelerate.h>
#include <atomic>

class AudioProcessor {
   public:
    // Band energy is normalised across a fixed decibel window rather than by
    // linear amplitude. Linear mapping put half the bar's travel inside 6 dB,
    // so a track mastered 8 dB hotter than a loudness-normalised one pinned the
    // bars while the quieter app barely moved. A 39 dB window turns that same
    // 8 dB difference into roughly a fifth of the bar.
    //
    // The bounds are chosen to keep the existing look at normal listening
    // levels: a mid-band block that used to render at half height still does,
    // while loud passages now have headroom instead of saturating.
    static constexpr float kFloorDb = -45.0f;
    static constexpr float kCeilingDb = -6.0f;

   private:
    static constexpr int kBlockSize = 512;
    static constexpr int kBands = 4;
    static constexpr float kAttack = 0.85f;   // fast rise
    static constexpr float kRelease = 0.40f;  // slower fall — more musical

    // Per-band make-up gain. Same weighting as the previous linear
    // 3.5/6/9/20 multipliers, expressed in dB so the whole chain stays in the
    // perceptual domain.
    static constexpr float kBandGainDb[kBands] = { 10.881f, 15.563f, 19.085f,
                                                   26.021f };

    // Below this the envelope is flushed to exactly zero, so silence stays
    // silent when a positive level offset is applied downstream.
    static constexpr float kSilenceEpsilon = 1e-4f;

    float sampleRate;
    int writePos = 0;
    float mono[kBlockSize] = {};
    float filtered[kBlockSize] = {};

    vDSP_biquad_Setup setups[kBands];
    alignas( 16 ) float delays[kBands][4] = {};

    float envelopes[kBands] = {};

    // Lock-free: audio thread writes, render thread reads
    // One atomic per band — fits in a cache line
    alignas( 64 ) std::atomic< float > bandParams[kBands] = {};

    // Written by the main thread on volume/route changes, read by the audio
    // thread. Applied before the window is clamped, so silence cannot be
    // lifted off the floor by a positive offset.
    std::atomic< float > levelOffsetDb{ 0.0f };

   public:
    explicit AudioProcessor( float sr = 48000.0f );
    ~AudioProcessor();

    // Called by CoreAudio — must be real-time safe (no alloc, no locks)
    void process( const float* __restrict__ buffer, int totalSamples );

    // Called by render thread — lock-free read
    float getBand( int i ) const;

    // Shifts every band by `db` before normalisation. Used for output volume
    // and per-device calibration.
    void setLevelOffsetDb( float db );

   private:
    enum class FilterType { LowPass, BandPass, HighPass };

    void processBlock();
    void setupBiquad( int idx, FilterType type, float freq, float q );
};

#endif  // AUDIOPROCESSOR_HPP
