//
//  AudioController.m
//  AudioJackUARTTest
//
//  Created by Rick on 2017/2/14.
//  Copyright © 2017年 Rick. All rights reserved.
//

#import "AudioController.h"

AudioController* audioController;
@interface AudioController () {
    MPVolumeView *myVolumeView;
    
    AudioComponentInstance audioUnit;
    AudioBuffer tempBuffer; // this will hold the latest data from the microphone
    SInt16      signalData[SAMPLE_COUNT];
    SInt16      signalDataPartial[SAMPLE_COUNT];
    SInt16      signalDataMF[SAMPLE_COUNT];
    SInt16      signalDataBI[SAMPLE_COUNT];
    SInt16      signalDataDIF[SAMPLE_COUNT];
    BOOL        signalDataTEMP[TEMP_DATA_LENGTH];
    BOOL        signalDataDIG[SERIAL_DATA_LENGTH];
    BOOL        signalDataAlcohol[ALCOHOL_DATA_LENGTH];
    UInt16      signalDataCounter;
    NSMutableString *signalRecord;
    BOOL        startRecording;
    
    float       orgVolume;
    /**/
    
    NSTimer     *pulseTimer;
    NSTimer     *resultTimer;
@public
    audioConnectingMode         mode;
    
    BOOL        statusStartTransfer;
    double      frequency;
    double      theta;
    int         dataWaveformIndex;
    int         dataWaveformMax;
    int         transferTimes;
    
    UInt16      sinWave250Hz[FR250Hz_PULSE_LENGTH];
    UInt16      sinWave125Hz[FR125Hz_PULSE_LENGTH];
    UInt16      sinWave62o5Hz[FR62o5Hz_PULSE_LENGTH];
    UInt16      dataWaveform[DATA_WAVEFORM_LENGTH];
}
@end

void checkStatus(int status){
    if (status) {
        printf("Status not 0! %d\n", status);
        //		exit(1);
    }
}

static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    
    // Because of the way our audio format (setup below) is chosen:
    // we only need 1 buffer, since it is mono
    // Samples are 16 bits = 2 bytes.
    // 1 frame includes only 1 sample
    AudioController *VC = (__bridge AudioController*)inRefCon;
    AudioBuffer buffer;
    
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = inNumberFrames * 2;
    buffer.mData = malloc( inNumberFrames * 2 );
    
    // Put buffer in a AudioBufferList
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    
    // Then:
    // Obtain recorded samples
    
    OSStatus status;
    
    status = AudioUnitRender([audioController audioUnit],
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList);
    
    checkStatus(status);
    
    // Now, we have the samples we just read sitting in buffers in bufferList
    // Process the new data
    if (VC->mode == TEMPERATURE_MODE) {
        [audioController processAudio4BT:&bufferList withFrameNumber:inNumberFrames];
    }
    else if ((VC->mode > TEMPERATURE_MODE)){
        [audioController processAudio:&bufferList withFrameNumber:inNumberFrames];
    }
    
    
    
    // release the malloc'ed data in the buffer we created earlier
    free(bufferList.mBuffers[0].mData);
    
    return noErr;
}

/**
 This callback is called when the audioUnit needs new data to play through the
 speakers. If you don't have any, just don't write anything in the buffers
 */
static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData) {
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    
    for (int i=0; i < ioData->mNumberBuffers; i++) {
        // we will only have 1 buffer, since audio format is mono
        AudioBuffer buffer = ioData->mBuffers[i];
        
        //		NSLog(@"  Buffer %d has %d channels and wants %d bytes of data.", i, (unsigned int)buffer.mNumberChannels, (unsigned int)buffer.mDataByteSize);
        
        
        // dont copy more data then we have, or then fits
        UInt32 size = min(buffer.mDataByteSize, [audioController tempBuffer].mDataByteSize);
        // copy temporary buffer data to output buffer
        memcpy(buffer.mData, [audioController tempBuffer].mData, size);
        // indicate how much data we wrote in the buffer
        buffer.mDataByteSize = size;
        
        /* uncomment to hear random noise */
        //		UInt16 *frameBuffer = buffer.mData;
        //		for (int j = 0; j < inNumberFrames; j++) {
        //			frameBuffer[j] += arc4random_uniform(1000);
        //		}
        
    }
    return noErr;
}

OSStatus RenderTone4Temperature(
                                void *inRefCon,
                                AudioUnitRenderActionFlags 	*ioActionFlags,
                                const AudioTimeStamp 		*inTimeStamp,
                                UInt32 						inBusNumber,
                                UInt32 						inNumberFrames,
                                AudioBufferList 			*ioData)

{
    const double amplitude = 0x7fff;
    const double sampleRate = 44100;
    
    AudioController *VC = (__bridge AudioController*)inRefCon;
    double frequency = 21000;
    double theta = VC->theta;
    double theta_increment = 2.0 * M_PI * frequency / sampleRate;
    
    for (int i=0; i < ioData->mNumberBuffers; i++) {
        // we will only have 1 buffer, since audio format is mono
        AudioBuffer buffer = ioData->mBuffers[i];
        
        // Generate the samples
        UInt16 *frameBuffer = buffer.mData;
        for (UInt32 frame = 0; frame < inNumberFrames; frame++)
        {
            frameBuffer[frame] = sin(theta) * amplitude;
            theta += theta_increment;
            if (theta > 2.0 * M_PI)
            {
                theta -= 2.0 * M_PI;
            }
        }
    }
    VC->theta = theta;
    
    return noErr;
}

OSStatus RenderTone4Alcohol(
                            void *inRefCon,
                            AudioUnitRenderActionFlags 	*ioActionFlags,
                            const AudioTimeStamp 		*inTimeStamp,
                            UInt32 						inBusNumber,
                            UInt32 						inNumberFrames,
                            AudioBufferList 			*ioData)

{
    AudioController *VC = (__bridge AudioController*)inRefCon;
    int dataWaveformIndex = VC->dataWaveformIndex;
    
    for (int i=0; i < ioData->mNumberBuffers; i++) {
        AudioBuffer buffer = ioData->mBuffers[i];
        // Generate the samples
        UInt16 *frameBuffer = buffer.mData;
        for (UInt32 frame = 0; frame < inNumberFrames; frame++){
            frameBuffer[frame] = VC->dataWaveform[dataWaveformIndex];
            if (VC->statusStartTransfer) {
                //            if ((VC->dataWaveformMax) > dataWaveformIndex) {
                if ((DATA_WAVEFORM_LENGTH>dataWaveformIndex)) {
                    dataWaveformIndex++;
                }
                else{
                    dataWaveformIndex = 0;
                    if (2<(VC->transferTimes)++) {
                        [VC clearWaveform];
                    }
                }
            }
        }
    }
    VC->dataWaveformIndex = dataWaveformIndex;
    
    return noErr;
}


@implementation AudioController

@synthesize audioUnit, tempBuffer;

/**
 Initialize the audioUnit and allocate our own temporary buffer.
 The temporary buffer will hold the latest data coming in from the microphone,
 and will be copied to the output when this is requested.
 */
- (id) init {
    self = [super init];
    
    OSStatus status;
    
    // Describe audio component
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get component
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    
    // Get audio units
    status = AudioComponentInstanceNew(inputComponent, &audioUnit);
    checkStatus(status);
    
    // Enable IO for recording
    UInt32 flag = 1;
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  kInputBus,
                                  &flag,
                                  sizeof(flag));
    checkStatus(status);
    
    // Enable IO for playback
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  kOutputBus,
                                  &flag,
                                  sizeof(flag));
    checkStatus(status);
    
    
    // Describe format
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate			= 44100.00;     // sample rate
    audioFormat.mFormatID			= kAudioFormatLinearPCM;    // PCM format
    audioFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket	= 1;
    audioFormat.mChannelsPerFrame	= 1;    // 1:mono ; 2:stereo
    audioFormat.mBitsPerChannel		= 16;   // sample bit
    audioFormat.mBytesPerPacket		= 2;
    audioFormat.mBytesPerFrame		= 2;
    
    // Apply format
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  kInputBus,
                                  &audioFormat,
                                  sizeof(audioFormat));
    checkStatus(status);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  kOutputBus,
                                  &audioFormat,
                                  sizeof(audioFormat));
    checkStatus(status);
    
    AudioUnitSetParameter(audioUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Global, 0, 1.0, 0);
    // Set input callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  kInputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    checkStatus(status);
    
    // Set output callback
    //	  callbackStruct.inputProc = playbackCallback;
    //    callbackStruct.inputProc = RenderTone4Temperature;
    callbackStruct.inputProc = RenderTone4Alcohol;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  kOutputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    checkStatus(status);
    
    // Disable buffer allocation for the recorder (optional - do this if we want to pass in our own)
    flag = 0;
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_ShouldAllocateBuffer,
                                  kAudioUnitScope_Output,
                                  kInputBus,
                                  &flag,
                                  sizeof(flag));
    
    
    
    // Allocate our own buffers (1 channel, 16 bits per sample, thus 16 bits per frame, thus 2 bytes per frame).
    // Practice learns the buffers used contain 512 frames, if this changes it will be fixed in processAudio.
    
    tempBuffer.mNumberChannels = 1;
    tempBuffer.mDataByteSize = 512;//512 * 2;
    tempBuffer.mData = malloc( 512 );//malloc( 512 * 2 );
    
    /* Master Volume Slider View Intialise */
    myVolumeView = [[MPVolumeView alloc] initWithFrame: CGRectMake(-1000, -100, 100, 100)];
    // Initialise
    status = AudioUnitInitialize(audioUnit);
    checkStatus(status);
    
    return self;
}

/**
 Clean up.
 */
- (void) dealloc {
    //	[super	dealloc];
    AudioUnitUninitialize(audioUnit);
    free(tempBuffer.mData);
}

#pragma mark - Start Function
/**
 Start the audioUnit. This means data will be provided from
 the microphone, and requested for feeding to the speakers, by
 use of the provided callbacks.
 */
- (void) temperatureAudioStart {
    mode = TEMPERATURE_MODE;
    //    signalRecord = [NSMutableString string];
    startRecording = NO;
    signalDataCounter = 0;
    self.temperatureResult = 0xffff;
    /* Set Output Volume to Max */
    [self setVolumeToMax];
    
    OSStatus status = AudioOutputUnitStart(audioUnit);
    checkStatus(status);
    
    //    resultTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(pollingResult:) userInfo:nil repeats:YES];
}

- (void) temperatureAudioStop {
    OSStatus status = AudioOutputUnitStop(audioUnit);
    checkStatus(status);
    
    NSLog(@"Temperature = %f",(float)self.temperatureResult/100);
    /* Set Output Volume to Original Volume */
    [self setVolumeToDefault];
}


- (void) alcoholAudioStart {
    mode = ALCOHOL_TEST_MODE;
    startRecording = NO;
    signalDataCounter = 0;
    dataWaveformIndex = 0;
    transferTimes = 0;
    self.alcoholTestResult = 0;
    [self generate62o5HzSinWave];
    [self generate125HzSinWave];
    
    /* Set Output Volume to Max */
    [self setVolumeToMax];
    
    OSStatus status = AudioOutputUnitStart(audioUnit);
    checkStatus(status);
    [audioController generateDataWaveform: AlcoholTestAudioCommand];
    
    //    pulseTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(pollingSerialData:) userInfo:nil repeats:YES];
}

- (void) lungAudioStart {
    mode = LUNG_CAPACITY_MODE;
    startRecording = NO;
    signalDataCounter = 0;
    dataWaveformIndex = 0;
    transferTimes = 0;
    self.lungCapacityResult = 0;
    [self generate62o5HzSinWave];
    [self generate125HzSinWave];
    
    /* Set Output Volume to Max */
    [self setVolumeToMax];
    
    OSStatus status = AudioOutputUnitStart(audioUnit);
    checkStatus(status);
    [audioController generateDataWaveform: LungCapacityAudioCommand];
    
    //    pulseTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(pollingSerialData:) userInfo:nil repeats:YES];
}

- (void) start {
    startRecording = NO;
    signalDataCounter = 0;
    dataWaveformIndex = 0;
    transferTimes = 0;
    [self generate62o5HzSinWave];
    [self generate125HzSinWave];
    
    /* Set Output Volume to Max */
    [self setVolumeToMax];
    
    OSStatus status = AudioOutputUnitStart(audioUnit);
    checkStatus(status);
    [audioController generateDataWaveform: 0xa0];
    
    //    pulseTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(pollingSerialData:) userInfo:nil repeats:YES];
    
}

/**
 Stop the audioUnit
 */
- (void) stop {
    //    [pulseTimer invalidate];
    OSStatus status = AudioOutputUnitStop(audioUnit);
    checkStatus(status);
    
    /* Set Output Volume to Original Volume */
    [self setVolumeToDefault];
    
    //        medianfilter(signalData, signalDataMF, SAMPLE_COUNT);
    //        binarize(signalDataMF, signalDataBI, SAMPLE_COUNT);
    //        differential(signalDataBI, signalDataDIF, SAMPLE_COUNT);
    //        signalConvert2bitsArray(signalDataDIF, signalDataDIG, SAMPLE_COUNT, SERIAL_DATA_LENGTH);
    //
    //        for (int i=0 ; i < SAMPLE_COUNT; i++) {
    //            if (i<SERIAL_DATA_LENGTH) {
    //                NSLog(@"\t%d\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i], signalDataDIG[i]);
    //            }
    //            else{
    //                NSLog(@"\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i]);
    //            }
    //        }
}
#pragma mark - System Volume Control
-(void) setVolumeToMax{
    // Create an instance of MPVolumeView and give it a frame
    //    MPVolumeView *myVolumeView = [[MPVolumeView alloc] initWithFrame: CGRectMake(-1000, -100, 100, 100)];
    myVolumeView.hidden = YES;
    /* Get Slider View Inside MPVolumeView */
    UISlider* volumeViewSlider = nil;
    for (UIView *view in [myVolumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            volumeViewSlider = (UISlider*)view;
            break;
        }
    }
    // retrieve system volume
    orgVolume = volumeViewSlider.value;
    
    // change system volume, the value is between 0.0f and 1.0f
    [volumeViewSlider setValue:1.0f animated:NO];
}
-(void) setVolumeToDefault{
    // Create an instance of MPVolumeView and give it a frame
    //    MPVolumeView *myVolumeView = [[MPVolumeView alloc] initWithFrame: CGRectMake(-1000, -100, 100, 100)];
    myVolumeView.hidden = YES;
    /* Get Slider View Inside MPVolumeView */
    UISlider* volumeViewSlider = nil;
    for (UIView *view in [myVolumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            volumeViewSlider = (UISlider*)view;
            break;
        }
    }
    // change system volume, the value is between 0.0f and 1.0f
    [volumeViewSlider setValue:orgVolume animated:NO];
}

#pragma mark - Timer Action
- (void) pollingResult:(NSTimer*)timer{
    if (self.temperatureResult >0) {
        NSLog(@"Get Result = %d", self.temperatureResult);
        [resultTimer invalidate];
    }
}

- (void) pollingSerialData:(NSTimer*)timer{
    NSLog(@"========================================");
    //    signalDataCounter = 0;
    //    [self alcoholSignalDecode];
}

#pragma mark - Signal Decode
- (void) alcoholSignalDecode{
    medianfilter(signalData, signalDataMF, SAMPLE_COUNT);
    binarize(signalDataMF, signalDataBI, SAMPLE_COUNT);
    differential(signalDataBI, signalDataDIF, SAMPLE_COUNT);
    signalConvert2bitsArray(signalDataDIF, signalDataDIG, SAMPLE_COUNT, SERIAL_DATA_LENGTH);
    /* Copy Data Aftr Find Header */
    for (int i = 0; i < (SERIAL_DATA_LENGTH-ALCOHOL_DATA_LENGTH+1); i++) {
        if (signalDataDIG[i]&&signalDataDIG[i+1]&&signalDataDIG[i+2]&&signalDataDIG[i+3]&&signalDataDIG[i+4]&&(!signalDataDIG[i+5])) {
            //            NSLog(@"!! FIND HEADER AT %d !!", i);
            memcpy(signalDataAlcohol, &signalDataDIG[i], sizeof(BOOL)*ALCOHOL_DATA_LENGTH);
            break;
        }
    }
    for (int i =0; i<SAMPLE_COUNT; i++) {
        signalData[i]=0;
    }
    
    //    NSLog(@"%02x %02x %02x %02x", [self getHeaderFrom:signalDataAlcohol], [self getLowByteFrom:signalDataAlcohol], [self getHighByteFrom:signalDataAlcohol], [self getCheckSumFrom:signalDataAlcohol]);
    UInt16 highByte = [self getByte1From:signalDataAlcohol];
    UInt16 lowByte  = [self getByte2From:signalDataAlcohol];
    UInt16 sum = (highByte+lowByte+1) & 0xff;
    UInt16 checkSumByte = [self getCheckSumFrom:signalDataAlcohol];
    UInt32 result;
    if (checkSumByte == sum) {
        if (mode == ALCOHOL_TEST_MODE) {
            result = lowByte;
            self.alcoholTestResult = (int)result;
        }
        else if (mode == LUNG_CAPACITY_MODE) {
            result = (highByte<<8)+lowByte;
            self.lungCapacityResult = (int)result;
        }
        else{
            NSLog(@"Function Mode Error");
            result = 0xffff;
        }
        NSLog(@"Data: %d (%02x,%02x,%02x)", (unsigned int)result, highByte, lowByte, checkSumByte);
    }
    else{
        NSLog(@"!! Recieve ERROR DATA !!(%02x,%02x,%02x)", highByte, lowByte, checkSumByte);
        result = 0xffff;
    }
    //    /* show serial data */
    //    for (int i=0 ; i < SERIAL_DATA_LENGTH; i++) {
    //        if (i<ALCOHOL_DATA_LENGTH) {
    //            NSLog(@"\t%d\t%d", signalDataDIG[i], signalDataAlcohol[i]);
    //        }
    //        else{
    //            NSLog(@"\t%d", signalDataDIG[i]);
    //        }
    //    }
    //    /* show signal */
    //    for (int i=0 ; i < SAMPLE_COUNT; i++) {
    //        if (i<SERIAL_DATA_LENGTH) {
    //            NSLog(@"\t%d\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i], signalDataDIG[i]);
    //        }
    //        else{
    //            NSLog(@"\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i]);
    //        }
    //    }
}

- (void) temperatureSignalDecode{
    medianfilter(signalData, signalDataMF, SAMPLE_COUNT);
    binarize(signalDataMF, signalDataBI, SAMPLE_COUNT);
    differential(signalDataBI, signalDataDIF, SAMPLE_COUNT);
    signalConvert2bitsArray(signalDataDIF, signalDataDIG, SAMPLE_COUNT, SERIAL_DATA_LENGTH);
    /* Copy Data Aftr Find Header */
    for (int i = 1; i < (SERIAL_DATA_LENGTH-ALCOHOL_DATA_LENGTH+1); i++) {
        if ((!signalDataDIG[i-1])&&signalDataDIG[i]&&signalDataDIG[i+1]&&signalDataDIG[i+2]&&signalDataDIG[i+3]&&signalDataDIG[i+4]&&(!signalDataDIG[i+5])) {
            //            NSLog(@"!! FIND HEADER AT %d !!", i);
            memcpy(signalDataAlcohol, &signalDataDIG[i], sizeof(BOOL)*ALCOHOL_DATA_LENGTH);
            break;
        }
    }
    for (int i =0; i<SAMPLE_COUNT; i++) {
        signalData[i]=0;
    }
    
    
    UInt16 lowByte = [self getByte1From:signalDataAlcohol];
    UInt16 highByte  = [self getByte2From:signalDataAlcohol];
    UInt16 sum = (highByte+lowByte+1) & 0xff;
    UInt16 checkSumByte = [self getCheckSumFrom:signalDataAlcohol];
    UInt32 result;
    if (checkSumByte == sum) {
        if (mode == TEMPERATURE_MODE) {
            result = (highByte<<8)+lowByte;
            //            self.temperatureResult = (int)result;
        }
        else{
            NSLog(@"Function Mode Error");
            result = 0xffff;
        }
        NSLog(@"Data: %d (%02x,%02x,%02x)", (unsigned int)result, lowByte, highByte, checkSumByte);
        self.temperatureResult = result;
        [self temperatureAudioStop];
    }
    else{
        NSLog(@"!! Recieve ERROR DATA !!(%02x,%02x,%02x)", lowByte, highByte, checkSumByte);
        result = 0xffff;
    }
    //    /* show serial data */
    //        for (int i=0 ; i < SERIAL_DATA_LENGTH; i++) {
    //            if (i<ALCOHOL_DATA_LENGTH) {
    //                NSLog(@"\t%d\t%d", signalDataDIG[i], signalDataAlcohol[i]);
    //            }
    //            else{
    //                NSLog(@"\t%d", signalDataDIG[i]);
    //            }
    //        }
    //    /* show signal */
    //    for (int i=0 ; i < SAMPLE_COUNT; i++) {
    //        if (i<SERIAL_DATA_LENGTH) {
    //            NSLog(@"\t%d\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i], signalDataDIG[i]);
    //        }
    //        else{
    //            NSLog(@"\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i]);
    //        }
    //    }
    
}
- (UInt32) temperatureSignalDecode2{
    memcpy(signalDataPartial, &signalData[TEMP_SECOND_SIGNAL_START], sizeof(SInt16)*TEMP_SIGNAL_LENGTH);
    medianfilter(signalDataPartial, signalDataMF, TEMP_SIGNAL_LENGTH);
    binarize(signalDataMF, signalDataBI, TEMP_SIGNAL_LENGTH);
    differential(signalDataBI, signalDataDIF, TEMP_SIGNAL_LENGTH);
    signalConvert2bitsArray(signalDataDIF, signalDataTEMP, TEMP_SIGNAL_LENGTH, TEMP_DATA_LENGTH);
    
    //    for (int i=0 ; i < TEMP_SIGNAL_LENGTH; i++) {
    //        NSLog(@"\t%d\t%d\t%d", signalDataMF[i], signalDataBI[i], signalDataDIF[i]);
    //    }
    
    UInt16 lowByte = [self getByte1From:signalDataTEMP];
    UInt16 highByte  = [self getByte2From:signalDataTEMP];
    UInt16 checkSumByte = [self getCheckSumFrom:signalDataTEMP];
    if (checkSumByte == (highByte+lowByte+1)) {
        UInt32 result = (highByte<<8)+lowByte;
        NSLog(@"Data: %d (%02x,%02x,%02x)", (unsigned int)result, lowByte, highByte, checkSumByte);
        return result;
    }
    else{
        NSLog(@"!! Recieve ERROR DATA !!(%02x,%02x,%02x)", highByte, lowByte, checkSumByte);
        return 0xFFFF;
    }
}

/**
 Change this funtion to decide what is done with incoming
 audio data from the microphone.
 Right now we copy it to our own temporary buffer.
 */
- (void) processAudio: (AudioBufferList*) bufferList withFrameNumber:(UInt32) inNumberFrames{
    AudioBuffer sourceBuffer = bufferList->mBuffers[0];
    
    // fix tempBuffer size if it's the wrong size
    if (tempBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
        free(tempBuffer.mData);
        tempBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
        tempBuffer.mData = malloc(sourceBuffer.mDataByteSize);
    }
    
    // copy incoming audio data to temporary buffer
    memcpy(tempBuffer.mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    
    SInt16 *samples;
    samples = (SInt16 *)tempBuffer.mData;
    
    if (SAMPLE_COUNT > signalDataCounter) {
        for (int i =0; i < inNumberFrames; i++) {
            if (SAMPLE_COUNT > signalDataCounter) {
                //                UInt16 sampleAmplitude = samples[i];//(samples[i]+0x7fff);
                SInt16 sampleAmplitude = samples[i];
                if ((PULSE_THRESHOLD<sampleAmplitude)&&(NO==startRecording)) {
                    startRecording = YES;
                }
                if ((startRecording)) {
                    signalData[signalDataCounter] = sampleAmplitude;
                    //                    NSLog(@"\t%d\t%d", signalData[signalDataCounter], signalDataCounter);
                    signalDataCounter++;
                    if ((SAMPLE_COUNT-1) < signalDataCounter) {
                        startRecording = NO;
                        signalDataCounter = 0;
                        //                        NSLog(@"tempBuffer copy to signalData Complete!");
                        [self alcoholSignalDecode];
                    }
                }
            }
        }
    }
}
- (void) processAudio4BT: (AudioBufferList*) bufferList withFrameNumber:(UInt32) inNumberFrames{
    AudioBuffer sourceBuffer = bufferList->mBuffers[0];
    
    // fix tempBuffer size if it's the wrong size
    if (tempBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
        free(tempBuffer.mData);
        tempBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
        tempBuffer.mData = malloc(sourceBuffer.mDataByteSize);
    }
    
    // copy incoming audio data to temporary buffer
    memcpy(tempBuffer.mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    
    SInt16 *samples;
    samples = (SInt16 *)tempBuffer.mData;
    
    if (SAMPLE_COUNT > signalDataCounter) {
        for (int i =0; i < inNumberFrames; i++) {
            if (SAMPLE_COUNT > signalDataCounter) {
                SInt16 sampleAmplitude = samples[i];
                if ((PULSE_THRESHOLD<sampleAmplitude)&&(NO==startRecording)) {
                    startRecording = YES;
                }
                if ((startRecording)) {
                    signalData[signalDataCounter] = sampleAmplitude;
                    //                    NSLog(@"\t%d\t%d", signalData[signalDataCounter], signalDataCounter);
                    signalDataCounter++;
                    if ((SAMPLE_COUNT-1) < signalDataCounter) {
                        startRecording = NO;
                        signalDataCounter = 0;
                        [self temperatureSignalDecode];
                        //                        [self temperatureAudioStop];
                    }
                }
            }
        }
    }
}

#pragma mark - Generate Output
- (void)clearWaveform{
    statusStartTransfer = NO;
    dataWaveformMax = 0;
    transferTimes = 0;
    for (int i = 0; i<DATA_WAVEFORM_LENGTH; i++) {
        dataWaveform[i] = 0;
    }
}

- (void)generateDataWaveform:(UInt8) u8_data{
    UInt8 u8_data2 = ((u8_data+1)&0xFF);
    for (int i = 0; i<DATA_WAVEFORM_LENGTH; i++) {
        dataWaveform[i] = 0;
    }
    statusStartTransfer = YES;
    dataWaveformIndex = 0;
    [self generateByteWaveform:0x00];
    [self generateByteWaveform:0x0F];
    [self generateByteWaveform:0xFF];
    [self generateByteWaveform:u8_data];
    [self generateByteWaveform:u8_data2];
    [self generateByteWaveform:0x00];
    dataWaveformMax = dataWaveformIndex;
}

- (void)generateByteWaveform:(UInt8) u8_data{
    
    BOOL temp;
    const UInt8 firstBit = 0x80;
    
    for (int i = 0; i<8; i++) {
        temp = (u8_data<<i)&firstBit;
        if (temp) {
            for (UInt32 frame = 0; frame < FR62o5Hz_PULSE_LENGTH; frame++)
            {
                dataWaveform[dataWaveformIndex++] = sinWave62o5Hz[frame];
            }
            //            NSLog(@"%d", temp);
        }
        else if(0==temp){
            for (UInt32 frame = 0; frame < FR125Hz_PULSE_LENGTH; frame++)
            {
                dataWaveform[dataWaveformIndex++] = sinWave125Hz[frame];
            }
            //            NSLog(@"%d", temp);
        }
    }
    
    //    for (int i = 0; i<dataWaveformMax; i++) {
    //        NSLog(@"[%04d]%08d", i, dataWaveform[i]);
    //    }
}

- (void)generate62o5HzSinWave{
    const double amplitude = 0x7fff;
    double theta_increment;
    theta_increment = THETA_INCREMENT_62o5Hz;
    for (UInt32 frame = 0; frame < 1024; frame++)
    {
        sinWave62o5Hz[frame] = sin(theta) * amplitude;
        theta += theta_increment;
        if (theta > 2.0 * M_PI)
        {
            theta -= 2.0 * M_PI;
            break;
        }
    }
}
- (void)generate125HzSinWave{
    const double amplitude = 0x7fff;
    double theta_increment;
    theta_increment = THETA_INCREMENT_125Hz;
    for (UInt32 frame = 0; frame < 512; frame++)
    {
        sinWave125Hz[frame] = sin(theta) * amplitude;
        theta += theta_increment;
        if (theta > 2.0 * M_PI)
        {
            theta -= 2.0 * M_PI;
            break;
        }
    }
}
- (void)generate250HzSinWave{
    const double amplitude = 0x7fff;
    double theta_increment;
    theta_increment = THETA_INCREMENT_250Hz;
    for (UInt32 frame = 0; frame < 512; frame++)
    {
        sinWave250Hz[frame] = sin(theta) * amplitude;
        theta += theta_increment;
        if (theta > 2.0 * M_PI)
        {
            theta -= 2.0 * M_PI;
            break;
        }
    }
}




#pragma mark - DSP Processing Function
void medianfilter(const SInt16* signal, SInt16* result, int N)
{
    
    //   Move window through all elements of the signal
    for (int i = 2; i < N - 2; ++i)
    {
        
        //   Pick up window elements
        SInt16 window[5];
        for (int j = 0; j < 5; ++j)
            window[j] = signal[i - 2 + j];
        //   Order elements (only half of them)
        for (int j = 0; j < 3; ++j)
        {
            
            //   Find position of minimum element
            int min = j;
            for (int k = j + 1; k < 5; ++k)
                if (window[k] < window[min])
                    min = k;
            //   Put found minimum element in its place
            const SInt16 temp = window[j];
            window[j] = window[min];
            window[min] = temp;
            
        }
        //   Get result - the middle element
        result[i - 2] = window[2];
        
    }
}

void binarize(const SInt16* signal, SInt16* result, int N)
{
    
    //   Move window through all elements of the signal
    for (int i = 0; i < N; i++)
    {
        if (signal[i] > 20000) {
            result[i] = 1;
        }
        else if (signal[i] < -20000){
            result[i] = -1;
        }
        else{
            result[i] = 0;
        }
    }
}

void differential(const SInt16* signal, SInt16* result, int N)
{
    result[0] = 0;
    result[N] = 0;
    result[N-1] = 0;
    result[N-2] = 0;
    for (int i = 1; i < (N-3); i++)
    {
        if ((signal[i]==-1)&&(signal[i-1]==0)) {
            if ((signal[i+1]==-1)&&(signal[i+2]==-1)) {
                result[i] = 1;
            }
            
        }
        else if ((signal[i]==-1)&&(signal[i-1]==1)) {
            if ((signal[i+1]==-1)&&(signal[i+2]==-1)) {
                result[i] = 1;
            }
        }
        else{
            result[i] = 0;
        }
    }
}

void signalConvert2bitsArray(const SInt16* signal, BOOL* result, int N, int dataLength){
    int pulse = 0;
    int prePulse = 0;
    int dataIndex = 0;
    
    for (int i=0; i < N; i++) {
        if (signal[i]&&(dataLength>dataIndex)) {
            pulse = i;
            if (!prePulse) {
                dataIndex = 0;
                result[dataIndex] = 1;
                prePulse = pulse;
            }
            else{
                int gap = round((double)((pulse-prePulse)/44))-1;
                for (int j=0; j<gap; j++) {
                    result[++dataIndex] = 0;
                }
                result[++dataIndex] = 1;
                prePulse = pulse;
            }
        }
    }
}

- (UInt8) getHeaderFrom:(BOOL*) signal{
    //    NSLog(@"\n%d%d%d%d%d%d %d%d%d%d%d%d%d%d %d%d%d%d%d%d%d%d %d%d%d%d%d%d%d%d",signal[0],signal[1],signal[2],signal[3],signal[4],signal[5],signal[6],signal[7],signal[8],signal[9],signal[10],signal[11],signal[12],signal[13],signal[14],signal[15],signal[16],signal[17],signal[18],signal[19],signal[20],signal[21],signal[22],signal[23],signal[24],signal[25],signal[26],signal[27],signal[28],signal[29]);
    UInt8 result = 0x00;
    int startPosition = 0;
    for (int i= startPosition; i<(startPosition+6); i++) {
        result <<= 1;
        if (signal[i]) {
            result +=1;
        }
    }
    
    return result;
}

- (UInt8) getByte1From:(BOOL*) signal{
    UInt8 result = 0x00;
    int startPosition = 6;
    for (int i= startPosition; i<(startPosition+8); i++) {
        result <<= 1;
        if (signal[i]) {
            result +=1;
        }
    }
    return result;
}

- (UInt8) getByte2From:(BOOL*) signal{
    UInt8 result = 0x00;
    int startPosition = 14;
    for (int i= startPosition; i<(startPosition+8); i++) {
        result <<= 1;
        if (signal[i]) {
            result +=1;
        }
    }
    return result;
}

- (UInt8) getCheckSumFrom:(BOOL*) signal{
    UInt8 result = 0x00;
    int startPosition = 22;
    for (int i= startPosition; i<(startPosition+8); i++) {
        result <<= 1;
        if (signal[i]) {
            result +=1;
        }
    }
    return result;
}


@end
