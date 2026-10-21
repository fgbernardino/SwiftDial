#import <XCTest/XCTest.h>
#import "../Telephone/ActiveCallViewController.h"
#import "../Telephone/AKSIPCall.h"

@interface CallWindowCallStub : NSObject
@property AKSIPCallState state;
@property(getter=isMicrophoneMuted) BOOL microphoneMuted;
@property(getter=isOnRemoteHold) BOOL onRemoteHold;
@end
@implementation CallWindowCallStub
@end

@interface CallWindowControllerStub : NSObject
@property NSTimeInterval callStartTime;
@property(copy) NSString *elapsedTime;
@property(copy) NSString *status;
@property(strong) CallWindowCallStub *call;
@end
@implementation CallWindowControllerStub
@end

@interface CallWindowTests : XCTestCase
@end

@implementation CallWindowTests
- (void)testElapsedTimeDoesNotReplaceMutedOrHeldStatus {
    CallWindowControllerStub *controller = [CallWindowControllerStub new];
    controller.call = [CallWindowCallStub new];
    controller.call.state = kAKSIPCallConfirmedState;
    ActiveCallViewController *view = [[ActiveCallViewController alloc] initWithNibName:@"unused"
                                                                     callController:(id)controller];
    for (NSString *status in @[@"mic muted", @"on hold", @"Connected"]) {
        controller.status = status;
        controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 3661.1;
        [view callTimerTick:nil];
        XCTAssertEqualObjects(controller.elapsedTime, @"01:01:01");
        XCTAssertEqualObjects(controller.status, status);
    }
    controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 61.1;
    [view callTimerTick:nil];
    XCTAssertEqualObjects(controller.elapsedTime, @"01:01");
}

- (void)testControlsFollowConnectionMuteAndRemoteHold {
    CallWindowControllerStub *controller = [CallWindowControllerStub new];
    controller.call = [CallWindowCallStub new];
    controller.callStartTime = NSDate.timeIntervalSinceReferenceDate;
    ActiveCallViewController *view = [[ActiveCallViewController alloc] initWithNibName:@"unused"
                                                                     callController:(id)controller];
    NSButton *mute = [NSButton new];
    NSButton *transfer = [NSButton new];
    [view setValue:mute forKey:@"muteButton"];
    [view setValue:transfer forKey:@"extensionTransferButton"];
    [view callTimerTick:nil];
    XCTAssertFalse(mute.enabled);
    XCTAssertFalse(transfer.enabled);
    controller.call.state = kAKSIPCallConfirmedState;
    [view callTimerTick:nil];
    XCTAssertTrue(mute.enabled);
    XCTAssertTrue(transfer.enabled);
    XCTAssertEqual(mute.state, NSControlStateValueOff);
    controller.call.microphoneMuted = YES;
    controller.call.onRemoteHold = YES;
    [view callTimerTick:nil];
    XCTAssertEqual(mute.state, NSControlStateValueOn);
    XCTAssertFalse(transfer.enabled);
    controller.call.state = kAKSIPCallDisconnectedState;
    [view callTimerTick:nil];
    XCTAssertFalse(mute.enabled);
    XCTAssertFalse(transfer.enabled);
}
@end
