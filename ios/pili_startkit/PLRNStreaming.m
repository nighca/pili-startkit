  //
//  PLRNStreaming.m
//  pili_startkit
//
//  Created by 何云旗 on 2019/12/3.
//  Copyright © 2019 Facebook. All rights reserved.
//

#import "PLRNStreaming.h"
#import <React/RCTBridgeModule.h>
#import <React/UIView+React.h>
#import <React/RCTEventDispatcher.h>

@implementation PLRNStreaming{
    RCTEventDispatcher *_eventDispatcher;
    BOOL _started;
    BOOL _muted;
    BOOL _focus;
    NSString *_camera;
}

const char *stateNames[] = {
    "Unknow",
    "Connecting",
    "Connected",
    "Disconnecting",
    "Disconnected",
    "Error"
};


const char *networkStatus[] = {
    "Not Reachable",
    "Reachable via WiFi",
    "Reachable via CELL"
};

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
    if ((self = [super init])) {
        [PLStreamingEnv initEnv];
        _eventDispatcher = eventDispatcher;
        _started = YES;
        _muted = NO;
        _focus = NO;
        _camera = @"front";

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
        self.internetReachability = [Reachability reachabilityForInternetConnection];
        [self.internetReachability startNotifier];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleInterruption:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:[AVAudioSession sharedInstance]];
        CGSize videoSize = CGSizeMake(480 , 640);
        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
        if (orientation <= AVCaptureVideoOrientationLandscapeLeft) {
            if (orientation > AVCaptureVideoOrientationPortraitUpsideDown) {
                videoSize = CGSizeMake(640 , 480);
            }
        }
    }
    
    return self;
};

- (void) setRtmpURL:(NSString *)rtmpURL
{
    _rtmpURL = rtmpURL;
    [self setSourceAndProfile];
}

- (void)setProfile:(NSDictionary *)profile{
    _profile = profile;
    [self setSourceAndProfile];
}

- (void) setSourceAndProfile{
    if(self.profile && self.rtmpURL){
        
                NSDictionary *video = self.profile[@"video"];
                NSDictionary *audio = self.profile[@"audio"];
                
                int *fps = [video[@"fps"] integerValue];
                int *bps = [video[@"bps"] integerValue];
                int *maxFrameInterval = [video[@"maxFrameInterval"] integerValue];
                //TODO
                double height = 800;
                double width = 640;
                
                //TODO videoProfileLevel 需要通过 分辨率 选择
                
                PLVideoStreamingConfiguration *videoStreamingConfiguration = [[PLVideoStreamingConfiguration alloc] initWithVideoSize:CGSizeMake(width, height) expectedSourceVideoFrameRate:fps videoMaxKeyframeInterval:maxFrameInterval averageVideoBitRate:bps videoProfileLevel:AVVideoProfileLevelH264Baseline31];
                
                PLVideoCaptureConfiguration *videoCaptureConfiguration = [PLVideoCaptureConfiguration defaultConfiguration];

                PLAudioCaptureConfiguration *audioCaptureConfiguration = [PLAudioCaptureConfiguration defaultConfiguration];
                // 音频编码配置
                PLAudioStreamingConfiguration *audioStreamingConfiguration = [PLAudioStreamingConfiguration defaultConfiguration];
                AVCaptureVideoOrientation orientation = (AVCaptureVideoOrientation)(([[UIDevice currentDevice] orientation] <= UIDeviceOrientationLandscapeRight && [[UIDevice currentDevice] orientation] != UIDeviceOrientationUnknown) ? [[UIDevice currentDevice] orientation]: UIDeviceOrientationPortrait);
                // 推流 session
          self.session = [[PLMediaStreamingSession alloc] initWithVideoCaptureConfiguration:videoCaptureConfiguration audioCaptureConfiguration:audioCaptureConfiguration videoStreamingConfiguration:videoStreamingConfiguration audioStreamingConfiguration:audioStreamingConfiguration stream:nil];
                self.session.delegate = self;
                
                //            UIImage *waterMark = [UIImage imageNamed:@"qiniu.png"];
                //            PLFilterHandler handler = [self.session addWaterMark:waterMark origin:CGPointMake(100, 300)];
                //            self.filterHandlers = [@[handler] mutableCopy];//TODO -  水印暂时注释
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIView *previewView = self.session.previewView;
                    [self addSubview:previewView];
                    [previewView setTranslatesAutoresizingMaskIntoConstraints:NO];
                    
                    NSLayoutConstraint *centerX = [NSLayoutConstraint constraintWithItem:previewView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0];
                    NSLayoutConstraint *centerY = [NSLayoutConstraint constraintWithItem:previewView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0];
                    NSLayoutConstraint *width = [NSLayoutConstraint constraintWithItem:previewView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0];
                    NSLayoutConstraint *height = [NSLayoutConstraint constraintWithItem:previewView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0];
                    
                    NSArray *constraints = [NSArray arrayWithObjects:centerX, centerY,width,height, nil];
                    [self addConstraints: constraints];
                    
                    NSString *log = [NSString stringWithFormat:@"Zoom Range: [1..%.0f]", self.session.videoActiveFormat.videoMaxZoomFactor];
                    NSLog(@"%@", log);
                    
                    if(_focus){
                        [self.session setSmoothAutoFocusEnabled:_focus];
                        [self.session setTouchToFocusEnable:_focus];
                    }
                    
                    if(_muted){
                        [self setMuted:_muted];
                    }
                });

    }
}

- (void)setStarted:(BOOL) started {
    if(started != _started){
        if(started){
            [self startSession];
            _started = started;
        }else{
            [self stopSession];
            _started = started;
        }
    }
}

-(void)setMuted:(BOOL) muted {
    _muted = muted;
    [self.session setMuted:muted];
}

-(void)setFocus:(BOOL) focus {
    _focus = focus;
    [self.session setSmoothAutoFocusEnabled:focus];
    [self.session setTouchToFocusEnable:focus];
}

-(void)setZoom:(NSNumber*) zoom {
    self.session.videoZoomFactor = [zoom integerValue];
}

-(void)setCamera:(NSString*)camera{
    if([camera isEqualToString:@"front"] || [camera isEqualToString:@"back"]){
        if(![camera isEqualToString:_camera]){
            _camera = camera;
            [self.session toggleCamera];
        }
    }
    
}


- (void)streamingSessionSendingBufferDidFull:(id)session {
    NSString *log = @"Buffer is full";
    NSLog(@"%@", log);
}

- (void)streamingSession:(id)session sendingBufferDidDropItems:(NSArray *)items {
    NSString *log = @"Frame dropped";
    NSLog(@"%@", log);
}



- (void)stopSession {
        [self.session stopStreaming];
}

- (void)startSession {
        NSURL *streamURL = [NSURL URLWithString:self.rtmpURL];
  [self.session startStreamingWithPushURL:streamURL feedback:^(PLStreamStartStateFeedback feedback) {
        dispatch_async(dispatch_get_main_queue(), ^{
          NSLog(@"success ");
        });
  }];
}

- (void)mediaStreamingSession:(PLMediaStreamingSession *)session streamStatusDidUpdate:(PLStreamStatus *)status {
    NSString *log = [NSString stringWithFormat:@"Stream Status: %@", status];
    NSLog(@"%@", log);
}

- (void)mediaStreamingSession:(PLMediaStreamingSession *)session streamStateDidChange:(PLStreamState)state {
    NSString *log = [NSString stringWithFormat:@"Stream State: %s", stateNames[state]];
    NSLog(@"%@", log);
    
//    switch (state) {
//        case PLStreamStateUnknow:
//            [_eventDispatcher sendInputEventWithName:@"onLoading" body:@{@"target": self.reactTag}];
//        [_eventDispatcher sendTextEventWithType:RCTTextEventTypeFocus reactTag:self.reactTag text:<#(NSString *)#> key:<#(NSString *)#> eventCount:<#(NSInteger)#>]
//            break;
//        case PLStreamStateConnecting:
//            [_eventDispatcher sendInputEventWithName:@"onConnecting" body:@{@"target": self.reactTag}];
//            break;
//        case PLStreamStateConnected:
//            [_eventDispatcher sendInputEventWithName:@"onStreaming" body:@{@"target": self.reactTag}];
//            break;
//        case PLStreamStateDisconnecting:
//
//            break;
//        case PLStreamStateDisconnected:
//            [_eventDispatcher sendInputEventWithName:@"onDisconnected" body:@{@"target": self.reactTag}];
//            [_eventDispatcher sendInputEventWithName:@"onShutdown" body:@{@"target": self.reactTag}]; //FIXME
//            break;
//        case PLStreamStateError:
//            [_eventDispatcher sendInputEventWithName:@"onIOError" body:@{@"target": self.reactTag}];
//            break;
//        default:
//            break;
//    }

}
- (void)mediaStreamingSession:(PLMediaStreamingSession *)session didDisconnectWithError:(NSError *)error {
    NSString *log = [NSString stringWithFormat:@"Stream State: Error. %@", error];
    NSLog(@"%@", log);
    [self startSession];
}

- (void)reachabilityChanged:(NSNotification *)notif{
    Reachability *curReach = [notif object];
    NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
    NetworkStatus status = [curReach currentReachabilityStatus];
    
    if (NotReachable == status) {
        // 对断网情况做处理
        [self stopSession];
    }
    
    NSString *log = [NSString stringWithFormat:@"Networkt Status: %s", networkStatus[status]];
    NSLog(@"%@", log);
}

- (void)handleInterruption:(NSNotification *)notification {
    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        NSLog(@"Interruption notification");
        
        if ([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeBegan]]) {
            NSLog(@"InterruptionTypeBegan");
        } else {
            // the facetime iOS 9 has a bug: 1 does not send interrupt end 2 you can use application become active, and repeat set audio session acitve until success.  ref http://blog.corywiles.com/broken-facetime-audio-interruptions-in-ios-9
            NSLog(@"InterruptionTypeEnded");
            AVAudioSession *session = [AVAudioSession sharedInstance];
            [session setActive:YES error:nil];
        }
    }
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
