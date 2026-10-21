//
//  ActiveCallViewController.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "ActiveCallViewController.h"

#import "AKNSWindow+Resizing.h"
#import "AKSIPCall.h"

#import "CallController.h"
#import "CallTransferController.h"
#import "EndedCallViewController.h"


@interface ActiveCallViewController () <NSMenuItemValidation>

@property(nonatomic, weak) IBOutlet NSTextField *displayedNameField;
@property(nonatomic, weak) IBOutlet NSTextField *statusField;
@property(nonatomic, weak) IBOutlet NSTextField *numberField;
@property(nonatomic, weak) IBOutlet NSTextField *durationField;
@property(nonatomic, weak) IBOutlet NSButton *muteButton;
@property(nonatomic, weak) IBOutlet NSButton *extensionTransferButton;

@property(nonatomic) IBOutlet NSProgressIndicator *callProgressIndicator;
@property(nonatomic) IBOutlet NSButton *hangUpButton;

@end

@implementation ActiveCallViewController

- (instancetype)initWithNibName:(NSString *)nibName callController:(CallController *)callController {
    self = [super initWithNibName:nibName bundle:nil];
    
    if (self != nil) {
        _enteredDTMF = [[NSMutableString alloc] init];
        [self setCallController:callController];
    }
    return self;
}

- (instancetype)init {
    NSString *reason = @"Initialize ActiveCallViewController with initWithCallController:";
    @throw [NSException exceptionWithName:@"AKBadInitCall" reason:reason userInfo:nil];
    return nil;
}

- (void)removeObservations {
    [[self displayedNameField] unbind:NSValueBinding];
    [[self statusField] unbind:NSValueBinding];
    [self.numberField unbind:NSValueBinding];
    [self.durationField unbind:NSValueBinding];
 }

- (IBAction)hangUpCall:(id)sender {
    [[self callController] hangUpCall];
}

- (IBAction)toggleCallHold:(id)sender {
    [[self callController] toggleCallHold];
}

- (IBAction)toggleMicrophoneMute:(id)sender {
    [[self callController] toggleMicrophoneMute];
    [self updateControls];
}

- (IBAction)showCallTransferSheet:(id)sender {
    if (self.callController.call.state != kAKSIPCallConfirmedState || self.callController.call.isOnRemoteHold) { return; }
    if (![[self callController] isCallOnHold]) {
        [[self callController] toggleCallHold];
    }
    
    CallTransferController *callTransferController = [[self callController] callTransferController];

    [[[self callController] window] beginSheet:[callTransferController window] completionHandler:nil];
}

- (void)startCallTimer {
    if ([self callTimer] != nil && [[self callTimer] isValid]) {
        return;
    }
    
    [self setCallTimer:
     [NSTimer scheduledTimerWithTimeInterval:0.2
                                      target:self
                                    selector:@selector(callTimerTick:)
                                    userInfo:nil
                                     repeats:YES]];
}

- (void)stopCallTimer {
    if ([self callTimer] != nil) {
        [[self callTimer] invalidate];
        [self setCallTimer:nil];
    }
}

- (void)callTimerTick:(NSTimer *)theTimer {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSInteger seconds = MAX(0, (NSInteger)(now - self.callController.callStartTime));
    [self updateControls];
    
    if (seconds < 3600) {
        [[self callController] setElapsedTime:[NSString stringWithFormat:@"%02ld:%02ld",
                                          (seconds / 60) % 60, seconds % 60]];
    } else {
        [[self callController]
         setElapsedTime:[NSString stringWithFormat:@"%02ld:%02ld:%02ld",
                    seconds / 3600, (seconds / 60) % 60, seconds % 60]];
    }
}

- (void)updateControls {
    AKSIPCall *call = self.callController.call;
    BOOL connected = call != nil && call.state == kAKSIPCallConfirmedState;
    self.muteButton.enabled = connected;
    self.muteButton.title = call.isMicrophoneMuted ? NSLocalizedString(@"Unmute", @"Unmute. Call menu item.") : NSLocalizedString(@"Mute", @"Mute. Call menu item.");
    self.muteButton.state = call.isMicrophoneMuted ? NSControlStateValueOn : NSControlStateValueOff;
    self.extensionTransferButton.enabled = connected && !call.isOnRemoteHold;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.extensionTransferButton.title = NSLocalizedString(@"Transfer…", @"Transfer call to an extension.");
    if (self.numberField != nil) {
        self.hangUpButton.title = NSLocalizedString(@"End Call", @"End Call. Call menu item.");
    }
    [self updateControls];
}

- (void)showProgress {
    if (self.numberField != nil) {
        [self.callProgressIndicator startAnimation:self];
    }
    self.hangUpButton.hidden = NO;
    [self updateControls];
}

- (void)showHangUp {
    [self.callProgressIndicator stopAnimation:nil];
    self.hangUpButton.hidden = NO;
    [self updateControls];
}

- (void)allowHangUp {
    self.hangUpButton.enabled = YES;
}

- (void)disallowHangUp {
    self.hangUpButton.enabled = NO;
}


#pragma mark -
#pragma mark AKActiveCallViewDelegate protocol

- (void)activeCallView:(AKActiveCallView *)sender didReceiveText:(NSString *)aString {
    NSCharacterSet *DTMFCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789*#abcdrABCDR"];
    
    BOOL isDTMFValid = YES;
    for (NSUInteger i = 0; i < [aString length]; ++i) {
        unichar digit = [aString characterAtIndex:i];
        if (![DTMFCharacterSet characterIsMember:digit]) {
            isDTMFValid = NO;
            break;
        }
    }
    
    if (isDTMFValid) {
        if ([[self enteredDTMF] length] == 0) {
            [[self enteredDTMF] appendString:aString];
            [[[self view] window] setTitle:[[self callController] displayedName]];
            
            if ([[self displayedNameField] lineBreakMode]!= NSLineBreakByTruncatingHead) {
                [[self displayedNameField] setLineBreakMode:NSLineBreakByTruncatingHead];
                [[[[self callController] endedCallViewController] displayedNameField] setSelectable:YES];
            }
            
            [[self callController] setDisplayedName:aString];
            
        } else {
            [[self enteredDTMF] appendString:aString];
            [[self callController] setDisplayedName:[self enteredDTMF]];
        }
        
        [[[self callController] call] sendDTMFDigits:aString];
    }
}


#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleMicrophoneMute:)) {
        if ([[[self callController] call] isMicrophoneMuted]) {
            [menuItem setTitle:NSLocalizedString(@"Unmute", @"Unmute. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Mute", @"Mute. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState) {
            return YES;
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(toggleCallHold:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            [[[self callController] call] isOnLocalHold]) {
            [menuItem setTitle:NSLocalizedString(@"Resume", @"Resume. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Hold", @"Hold. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(showCallTransferSheet:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(hangUpCall:)) {
        [menuItem setTitle:NSLocalizedString(@"End Call", @"End Call. Call menu item.")];

        return self.hangUpButton.isEnabled;
    }
    
    return YES;
}

@end
