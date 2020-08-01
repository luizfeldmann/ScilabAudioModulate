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

#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include "portaudio.h"

#ifdef BUILD_DLL
    #define DLL_EXPORT __declspec(dllexport)
#else
    #define DLL_EXPORT __declspec(dllimport)
#endif

#define PA_SAMPLE_TYPE  paFloat32
typedef float SAMPLE;
#define SAMPLE_SILENCE  (0.0f)

struct recData
{
    double* buffer;
    PaStream* stream;

    int frameIndex;
    int maxFrameIndex;
};

static struct recData sessionData;

static int __cdecl recordCallback( const void *inputBuffer, void *outputBuffer,
                           unsigned long framesPerBuffer,
                           const PaStreamCallbackTimeInfo* timeInfo,
                           PaStreamCallbackFlags statusFlags,
                           void *userData )
{
    if (sessionData.buffer == NULL || inputBuffer == NULL)
        return paBadBufferPtr;

    int retcode;
    unsigned long framesLeft, framesToCalc;

    framesLeft = sessionData.maxFrameIndex - sessionData.frameIndex;
    if( framesLeft < framesPerBuffer )
    {
        framesToCalc = framesLeft;
        retcode = paComplete;
    }
    else
    {
        framesToCalc = framesPerBuffer;
        retcode = paContinue;
    }

    double *dst_ptr = &sessionData.buffer[sessionData.frameIndex];
    const SAMPLE *src_ptr = (const SAMPLE*)inputBuffer;

    for( unsigned int i = 0; i < framesToCalc; i++ )
        *dst_ptr++ = (double)*src_ptr++;

    sessionData.frameIndex += framesToCalc;

    return retcode;
}

DLL_EXPORT void __cdecl OpenCapture(int* sampleRate)
{
    sessionData.buffer = NULL;
    sessionData.frameIndex = 0;
    sessionData.maxFrameIndex = 0;
    sessionData.stream = NULL;

    PaError err = paNoError;
    if ( (err = Pa_Initialize()) != paNoError )
        goto exit;

    PaStreamParameters inputParameters;
    if ((inputParameters.device = Pa_GetDefaultInputDevice()) == paNoDevice)
    {
        fprintf(stderr, "Error: No default input device.\n");
        goto exit;
    }
    else
    {
        inputParameters.channelCount = 1;
        inputParameters.sampleFormat = PA_SAMPLE_TYPE;
        inputParameters.suggestedLatency = Pa_GetDeviceInfo( inputParameters.device )->defaultLowInputLatency;
        inputParameters.hostApiSpecificStreamInfo = NULL;
    }

    if ( (err = Pa_OpenStream(
              &sessionData.stream,
              &inputParameters,
              NULL,
              *sampleRate,
              512,
              paClipOff,
              recordCallback,
              NULL )) != paNoError)
    {
        fprintf(stderr, "\nPa_OpenStream failed\n");
        goto exit;
    }

    if (sessionData.stream == NULL)
    {
        fprintf(stderr, "\nPa_OpenStream failed\n");
        goto exit;
    }

    return; // -- success

    exit:
    Pa_Terminate();
    if( err != paNoError )
        fprintf( stderr, "\nError: %d %s\n", err, Pa_GetErrorText( err ) );
}

DLL_EXPORT void __cdecl Capture(int *numSamples, double buffer[])
{
    PaError err;

    sessionData.frameIndex = 0;
    sessionData.buffer = &buffer[0];
    sessionData.maxFrameIndex = *numSamples;

//    printf("\nPa_StartStream with maxFrameIndex = %d and ptrdata = %ld and buffer = %ld\n", data->maxFrameIndex, (long int)*ptrdata, (long int)data->buffer);
    if( (err = Pa_StartStream( sessionData.stream )) != paNoError )
    {
        fprintf(stderr, "\nPa_StartStream failed!");
        return;
    }

    while( ( err = Pa_IsStreamActive( sessionData.stream ) ) == 1 )
        Pa_Sleep(100);

    Pa_StopStream(sessionData.stream);
}

DLL_EXPORT void __cdecl CloseCapture()
{
    if (sessionData.stream == NULL)
        return;

    Pa_CloseStream( sessionData.stream );
    Pa_Terminate();
}

int playCallback( const void *inputBuffer, void *outputBuffer,
                         unsigned long framesPerBuffer,
                         const PaStreamCallbackTimeInfo* timeInfo,
                         PaStreamCallbackFlags statusFlags,
                         void *userData )
{
    struct recData *data = userData;

    if (data == NULL || outputBuffer == NULL)
        return paBadBufferPtr;

    double *rptr = &data->buffer[data->frameIndex];
    SAMPLE *wptr = (SAMPLE*)outputBuffer;

    int retcode;
    unsigned int framesToCalc;
    unsigned int framesLeft = data->maxFrameIndex - data->frameIndex;

    if( framesLeft < framesPerBuffer )
    {
        framesToCalc = framesLeft;
        retcode = paComplete;
    }
    else
    {
        framesToCalc = framesPerBuffer;
        retcode = paContinue;
    }

    for( unsigned int i = 0; i < framesToCalc; i++ )
        *wptr++ = (SAMPLE)*rptr++;


    data->frameIndex += framesToCalc;

    return retcode;
}

DLL_EXPORT void __cdecl Playback(double buffer[], int* sampleRate, int* numSamples)
{
    if (buffer == NULL || sampleRate == NULL || numSamples == NULL)
        return;

    if (*sampleRate == 0 || *numSamples == 0)
        return;

    struct recData data = {
        .frameIndex = 0,
        .maxFrameIndex = *numSamples,
        .buffer = buffer,
    };

    PaStreamParameters outputParameters;
    PaStream* stream;

    PaError err = paNoError;
    if ( (err = Pa_Initialize()) != paNoError )
    {
        fprintf(stderr, "\nError: Pa_Initialize()");

        term:
        Pa_Terminate();
        return;
    }

    outputParameters.device = Pa_GetDefaultOutputDevice();
    if (outputParameters.device == paNoDevice)
    {
        fprintf(stderr, "\nError: No default output device.");
        goto term;
    }

    outputParameters.channelCount = 1;
    outputParameters.sampleFormat =  PA_SAMPLE_TYPE;
    outputParameters.suggestedLatency = Pa_GetDeviceInfo( outputParameters.device )->defaultLowOutputLatency;
    outputParameters.hostApiSpecificStreamInfo = NULL;

    err = Pa_OpenStream(
              &stream,
              NULL,
              &outputParameters,
              *sampleRate,
              512,
              paClipOff,
              playCallback,
              &data );
    if( err != paNoError )
        goto exit;

    if( stream )
    {
        if ( (err = Pa_StartStream( stream )) != paNoError)
            goto exit;

        while( ( err = Pa_IsStreamActive( stream ) ) == 1 ) // continue
            Pa_Sleep(100);

        if( err < 0 ) // something went wrong
            goto exit;

        err = Pa_CloseStream( stream );
    }

    exit:
    Pa_Terminate();
    if( err != paNoError )
        fprintf( stderr, "\nError: %d %s\n", err, Pa_GetErrorText( err ) );
}
