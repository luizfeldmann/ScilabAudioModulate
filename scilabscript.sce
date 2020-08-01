// =============================================================================
// Copyright (C) 2020  Luiz Gustavo Pfitscher e Feldmann
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
// =============================================================================

clear

// loads the portAudio interface library
wrapperlib_path = pwd() + "\ScilabAudioWrapper.dll";

if (link() == []) then
    Lib = link(wrapperlib_path, ["OpenCapture", "CloseCapture", "Capture", "Playback"], 'c');
end

// creates the capture session
sampleRate = 22050;
call("OpenCapture", sampleRate, 1, "i");

// perform capture in loop
recDurationSec = 0.05;                       // how long each "animation frame" will record audio
numSamples_audio = ceil(recDurationSec*sampleRate);     // number of audio samples recorded in baseband

times = linspace(0, recDurationSec, numSamples_audio); // vector of time for each audio baseband sample
[m,n] = size(times);

baseband_frequencies=sampleRate*(0:(numSamples_audio/2))/numSamples_audio; // vector of Hz frequencies for fft in baseband
numBaseFreqPlot = size(baseband_frequencies,'*')/2 // how many frequencies will be plotted in baseband spectrum
peakSampleAmplitude = 0;

// fm modulation data
fm_carrier_freq = 1e6; // 1 MHz -- if this number is too high where will be too many samples and computation time will increase
fm_deltaF = fm_carrier_freq/5000;
fm_sample_rate = 5*fm_carrier_freq; //
fm_num_samples = recDurationSec*fm_sample_rate;
fm_time_points = linspace(0, recDurationSec, fm_num_samples); // a set of time values from 0 to recDuration spaces by sampling period 1/fm_sample_rate
fm_freq_points = fm_sample_rate*(0:(fm_num_samples/2))/fm_num_samples; // vector of Hz frequencies for fft in passband
fm_freq_points_count = size(fm_freq_points, '*');
fm_plot_range = 1.02

while 1
    samples_baseband = call("Capture", numSamples_audio, 1, "i", "out", [m,n], 2, "d"); // record a few samples
    peakSampleAmplitude = max(peakSampleAmplitude, max(abs(samples_baseband))); // get the peak sample
    samples_baseband = samples_baseband ./ peakSampleAmplitude; // normalize samples below 1

    baseband_spectrum = abs(fft(samples_baseband));

    for i=1:numSamples_audio
        integrated_message(i) = sum(baseband_spectrum(1:i))*(1/sampleRate);
    end

    samples_interpol = interp1(times,integrated_message,fm_time_points,'linear');

    fm_instantaneous_phase = 2*%pi*(fm_carrier_freq*fm_time_points + fm_deltaF*samples_interpol);
    fm_signal = cos(fm_instantaneous_phase);

    fm_spectrum = abs(fft(fm_signal));

    // plotting
    drawlater();
    clf();

    // plot baseband spectrum
    subplot(211);
    plot(baseband_frequencies(1:numBaseFreqPlot),baseband_spectrum(1:numBaseFreqPlot));
    h = gca();
    h.data_bounds = [0, 0; baseband_frequencies(numBaseFreqPlot), 100];

    // plot fm spectrum
    subplot(212);
    plot(fm_freq_points, fm_spectrum(1:fm_freq_points_count) );
    h = gca();
    h.data_bounds = [fm_carrier_freq/fm_plot_range, 0; fm_carrier_freq*fm_plot_range, 1000];

    drawnow();
end

// close the capture session and release the library
call("CloseCapture");
//call("Playback", samples2, 1, "d", sampleRate, 2, "i", numSamples, 3, "i");
ulink(Lib);
disp("Done!");
