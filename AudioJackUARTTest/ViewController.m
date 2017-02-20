//
//  ViewController.m
//  AudioJackUARTTest
//
//  Created by Rick on 2017/2/14.
//  Copyright © 2017年 Rick. All rights reserved.
//

#import "ViewController.h"
#import "AudioController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController () {
    BOOL        statusHeatUpFinished;
    NSTimer     *pollingResultTimer;
    int         heatupEvent;
    int         alcoholTestResult;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)viewWillAppear:(BOOL)animated {
    
    [AVAudioSession sharedInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    audioController = [[AudioController alloc] init];
    if ([self isHeadsetPluggedIn]) {
        [self startAudioCommunication];
    }
}

#pragma mark - Audio Communication
- (void) startAudioCommunication{
    statusHeatUpFinished = NO;
    [audioController alcoholAudioStart];
    /* start polling result timer */
    pollingResultTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(pollingHeatUpTimerCallback:) userInfo:nil repeats:YES];
}

#pragma mark - Timer Callback
- (void) pollingHeatUpTimerCallback:(NSTimer*)timer{
    if (audioController.alcoholTestResult >0) {
        NSLog(@"Heat Up Sataus: %d", audioController.alcoholTestResult);
        heatupEvent = audioController.alcoholTestResult;
        if (heatupEvent > 100) {
            [pollingResultTimer invalidate];
            statusHeatUpFinished = YES;
            /* polling alcohol test result */
            alcoholTestResult = -1;
            pollingResultTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(pollingResultTimerCallback:) userInfo:nil repeats:YES];
        }
    }
}

- (void) pollingResultTimerCallback:(NSTimer*)timer{
    if ((statusHeatUpFinished) && (audioController.alcoholTestResult<110)) {
        //        NSLog(@"Alcohol Test Result: %d", iosAudio.alcoholTestResult);
        alcoholTestResult = audioController.alcoholTestResult;
        if (alcoholTestResult >= 0) {
            [pollingResultTimer invalidate];
            [audioController stop];
            /* perform segue and result to next view controller */
            [self performSegueWithIdentifier:@"BACGuideToBACResult" sender:0];
        }
    }
}

#pragma mark - Headphone Plug Detection
- (BOOL)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

- (void)audioRouteChangeListenerCallback:(NSNotification*)notification
{
    NSDictionary *interuptionDict = notification.userInfo;
    
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    switch (routeChangeReason) {
            
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"AVAudioSessionRouteChangeReasonNewDeviceAvailable");
            NSLog(@"Headphone/Line plugged in");
            break;
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"AVAudioSessionRouteChangeReasonOldDeviceUnavailable");
            NSLog(@"Headphone/Line was pulled. Stopping player....");
            [audioController stop];
            break;
            
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // called at start - also when other audio wants to play
            NSLog(@"AVAudioSessionRouteChangeReasonCategoryChange");
            break;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
