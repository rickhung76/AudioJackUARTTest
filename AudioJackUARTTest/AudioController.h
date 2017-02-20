//
//  AudioController.h
//  AudioJackUARTTest
//
//  Created by Rick on 2017/2/14.
//  Copyright © 2017年 Rick. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPVolumeView.h>

@interface AudioController : NSObject {
    
}
@property (readonly) AudioComponentInstance audioUnit;
@property (readonly) AudioBuffer tempBuffer;
@property (nonatomic,assign) int temperatureResult;
@property (nonatomic,assign) int alcoholTestResult;
@property (nonatomic,assign) int lungCapacityResult;
//@property (readonly) AudioBuffer saquenceBuffer;

- (void) start;
- (void) stop;
- (void) temperatureAudioStart;
- (void) temperatureAudioStop;
- (void) alcoholAudioStart;
- (void) lungAudioStart;

- (void) setVolumeToMax;
- (void) setVolumeToDefault;

- (void) processAudio: (AudioBufferList*) bufferList withFrameNumber:(UInt32) inNumberFrames;
- (void) processAudio4BT: (AudioBufferList*) bufferList withFrameNumber:(UInt32) inNumberFrames;
- (void) generateDataWaveform:(UInt8) u8_data;
- (void) clearWaveform;

@end

extern AudioController* audioController;

typedef enum {
    NONE = 0,
    TEMPERATURE_MODE,
    ALCOHOL_TEST_MODE,
    LUNG_CAPACITY_MODE,
} audioConnectingMode;

#define AlcoholTestAudioCommand     0xc0
#define LungCapacityAudioCommand    0xa0

#define kOutputBus  0
#define kInputBus   1

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

#define SAMPLE_COUNT                    5500
#define TEMP_SECOND_SIGNAL_START        1700
#define TEMP_SIGNAL_LENGTH              1800
#define TEMP_DATA_LENGTH                30
#define ALCOHOL_SECOND_SIGNAL_START     2000
#define ALCOHOL_SIGNAL_LENGTH           2000
#define SERIAL_DATA_LENGTH              (int) SAMPLE_COUNT/44
#define ALCOHOL_DATA_LENGTH             30
#define PULSE_THRESHOLD                 24000
#define BINARIZE_THRESHOLD              25000

#define SAMPLE_RATE                     44100
#define FR250Hz                         250
#define FR125Hz                         125
#define FR62o5Hz                        62.5
#define FR250Hz_PULSE_LENGTH            176
#define FR125Hz_PULSE_LENGTH            352
#define FR62o5Hz_PULSE_LENGTH           704
#define HIGH_BIT_PULSE_LENGTH           FR62o5Hz_PULSE_LENGTH
#define DATA_WAVEFORM_LENGTH            HIGH_BIT_PULSE_LENGTH * 8 * 6
#define THETA_INCREMENT_250Hz           (2 * M_PI * FR250Hz / SAMPLE_RATE)
#define THETA_INCREMENT_125Hz           (2 * M_PI * FR125Hz / SAMPLE_RATE)
#define THETA_INCREMENT_62o5Hz          (2 * M_PI * FR62o5Hz / SAMPLE_RATE)
