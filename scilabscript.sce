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
audio_sampleRate = 44100;
call("OpenCapture", audio_sampleRate, 1, "i");

// perform capture in loop
recDurationSec = 0.01;                       // how long each "animation frame" will record audio
numSamples_audio = floor(recDurationSec*audio_sampleRate);     // number of audio samples recorded in baseband

times = linspace(0, numSamples_audio/audio_sampleRate, numSamples_audio); // vector of time for each audio baseband sample
[m,n] = size(times);

baseband_frequencies=audio_sampleRate*(0:(numSamples_audio/2))/numSamples_audio; // vector of Hz frequencies for fft in baseband
numBaseFreqPlot = size(baseband_frequencies,'*')/2 // how many frequencies will be plotted in baseband spectrum
peakSampleAmplitude = 0;

// fm/pm modulation data
carrier_freq = 1e5;
fm_deltaF = carrier_freq/50;
pm_deltaPhi = 2; 

modul_sample_rate = 4*carrier_freq;
modul_num_samples = floor(recDurationSec*modul_sample_rate);
modul_time_points = linspace(0, modul_num_samples/modul_sample_rate, modul_num_samples); // a set of time values from 0 to recDuration spaces by sampling period 1/fm_sample_rate
modul_freq_points = modul_sample_rate*(0:(modul_num_samples/2))/modul_num_samples; // vector of Hz frequencies for fft in passband
modul_freq_points_count = size(modul_freq_points, '*');
modul_plot_range = 1.1


while 1
    // baseband
    samples_baseband = call("Capture", numSamples_audio, 1, "i", "out", [m,n], 2, "d"); // record a few samples
    peakSampleAmplitude = max(peakSampleAmplitude, max(abs(samples_baseband))); // get the peak sample
    samples_baseband = samples_baseband ./ peakSampleAmplitude; // normalize samples below 1

    baseband_spectrum = abs(fft(samples_baseband));

    // PM
    samples_interpol = interp1(times,samples_baseband,modul_time_points,'spline');
    pm_signal = cos(2*%pi*carrier_freq*modul_time_points + pm_deltaPhi*samples_interpol);
    pm_spectrum = abs(fft(pm_signal));
    
    // FM
    integrated_message(1) = samples_baseband(1)*(1/audio_sampleRate);
    for i=2:numSamples_audio
        integrated_message(i) = integrated_message(i-1) + samples_baseband(i)*(1/audio_sampleRate);
    end
    
    integrated_interpolated = interp1(times,integrated_message,modul_time_points,'spline');

    fm_signal = cos(2*%pi*carrier_freq*modul_time_points + 2*%pi*fm_deltaF*integrated_interpolated);
    fm_spectrum = abs(fft(fm_signal));
    
    // plotting
    drawlater();
    clf();

    // plot baseband spectrum
    subplot(311);
    title("Base");
    plot(baseband_frequencies(1:numBaseFreqPlot),baseband_spectrum(1:numBaseFreqPlot));
    h = gca();
    h.data_bounds = [0, 0; baseband_frequencies(numBaseFreqPlot), 100];
    
    // plot pm spectrum
    subplot(312);
    title("PM");
    plot(modul_freq_points, pm_spectrum(1:modul_freq_points_count) );
    h = gca();
    h.data_bounds = [carrier_freq/modul_plot_range, 0; carrier_freq*modul_plot_range, 1000];
    
    // plot fm spectrum
    subplot(313);
    title("FM");
    plot(modul_freq_points, fm_spectrum(1:modul_freq_points_count) );
    h = gca();
    h.data_bounds = [carrier_freq/modul_plot_range, 0; carrier_freq*modul_plot_range, 1000];

    drawnow();
end

// close the capture session and release the library
call("CloseCapture");
//call("Playback", samples2, 1, "d", sampleRate, 2, "i", numSamples, 3, "i");
ulink(Lib);
disp("Done!");
