#import <AudioToolbox/AudioToolbox.h>
#import "SpringBoard/SBUIController.h"
#import <SpringBoard/SBBacklightController.h>
#import <SpringBoard/SBDeviceLockController.h>
#import <SpringBoard/SBLockScreenManager.h>
#import <SpringBoardUIServices/SBUIBiometricEventMonitor.h>
#import <BiometricKit/BiometricKit.h>
#import <SpringBoard/SBReachabilityTrigger.h>
#import <SpringBoardUI/SBUISound.h>
#import <SpringBoard/SBSoundController.h>
#import <SpringBoard/SBUserAgent.h>
#import <AccessibilityUtilities/AXSpringBoardServer.h>
#import <SpringBoard/SBControlCenterController.h>
#import <SpotlightUI/SPUISearchViewController.h>

#import "Header.h"


@interface SBReachabilityTrigger (YourCategory)
- (unsigned long long int)doSth;
@end


%hook SBReachabilityTrigger
%new
_Bool secondTap;
%new
_Bool secondTapDisplayed;

%new
static NSLock *lock;

%new(v@:)
- (unsigned long long int)doSth
{

	// dont do anthing for first tap id double tap
	[lock lock];
	if (secondTap)
	{

		// if displayed, do not display again
		if (secondTapDisplayed)
		{
			[lock unlock];
			return 0;
		}

		 BOOL fingerOn = [[%c(SBUIBiometricEventMonitor) sharedInstance] isFingerOn];
		if (fingerOn)
		{
			[[%c(AXSpringBoardServer) server] openSiri];
		}

		
		// not displayed, continue
		secondTapDisplayed = YES;

		[[%c(SBUIController) sharedInstance]handleMenuDoubleTap];

		[lock unlock];
		return 0;
	}
	[lock unlock];

	/* single tap case below */
	
	/* single tap and hold */
	BOOL isFingerOn = [[%c(SBUIBiometricEventMonitor) sharedInstance] isFingerOn];
	if (isFingerOn)
	{
		id lockScreen = [%c(SBLockScreenManager) sharedInstance];
		[lockScreen hasUIEverBeenLocked];
		_Bool locked =  MSHookIvar<_Bool>(lockScreen, "_isUILocked");

		if (!locked)
		{
			[[%c(SBUserAgent) sharedUserAgent] lockAndDimDevice];
		}
	}

	/* single tap only */
	else
	{
		
		[[%c(SBUIController) sharedInstance]clickedMenuButton];

		/* find out if displaying special view */
		/* view that home button method called does not work as expected*/
		id server = [%c(AXSpringBoardServer) server];

		/* Special View : Siri */
		BOOL siriOn = [server isSiriVisible];

		/* Special View : Notification Center */
		BOOL notficationVisible = [server isNotificationCenterVisible];

		/* Special View : Control Center */
		BOOL controlCenterVisible = [server isControlCenterVisible];

		/* Special View : Spotlight */
		id spotlightViewController = [%c(SPUISearchViewController) sharedInstance];
		bool spotlightVisible = [spotlightViewController isVisible];

		/* dismiss special views */
		if (siriOn)
		{
			[server dismissSiri];
		}
		else if (notficationVisible)
			[server hideNotificationCenter];
		else if (controlCenterVisible)
			[[%c(SBControlCenterController) sharedInstance] dismissAnimated:YES];
		else if (spotlightVisible)
			[spotlightViewController dismissAnimated:YES completionBlock:nil];

	}


	return 0;
}


- (void)biometricEventMonitor:(id)arg1 handleBiometricEvent:(unsigned long long)arg2
{


	if (arg2 == 1)
{
	// reset
        [lock lock];
        secondTap = NO;
        secondTapDisplayed = NO;
        [lock unlock];

        // test second tap
        unsigned long long currentNumTap =  MSHookIvar<unsigned long long>(self, "_currentNumberOfTaps");
        if (currentNumTap == 1)
        {
                [lock lock];
                secondTap = YES;
                [lock unlock];
        }

        double delayInSeconds = 0.3;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);

        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

                [self doSth];

        });
}
	%orig;
}

- (id)initWithDelegate:(id)arg1
{
	lock = [NSLock new];

	secondTapDisplayed = NO;
	secondTap = NO;

	return %orig;
}

%end

%hook SBReachabilityManager
- (void)_toggleReachabilityModeWithRequestingObserver:(id)arg1
{
}

%end

%hook SBUIBiometricEventMonitor

//If either of these methods are enabled, they prevent touchID events from being sent to
//the touch unlock controller while the device is locked and a passcode isn't enabled.
//So, we make them do nothing if the device doesn't have a passcode, so this tweak can work.
- (void)noteScreenDidTurnOff {
}
- (void)noteScreenWillTurnOff {
}

%end

@implementation TouchUnlockController


+(id) sharedInstance
{
	return self;
}

-(void)vibrate
{
	int duration = 70;

		// Create your vibration
		SBUISound *sound = [[%c(SBUISound) alloc] init];
		sound.repeats = NO;
		sound.systemSoundID = 0;

		// Create an array for your vibration pattern
		NSMutableArray* vibrationPatternArray = [[NSMutableArray alloc] init];

		// Create your vibration pattern

		// Vibrate for 500 ms
		[vibrationPatternArray addObject:@(YES)];
		[vibrationPatternArray addObject:@(duration)];

		// Create a dict to hold vibration pattern and the intensity of the vibration
		NSMutableDictionary* vibrationPatternDict = [[NSMutableDictionary alloc] init];

		[vibrationPatternDict setObject:vibrationPatternArray forKey:@"VibePattern"];
		[vibrationPatternDict setObject:@(1) forKey:@"Intensity"];

		sound.vibrationPattern = vibrationPatternDict;

		// Actually play the vibration
		[(SBSoundController *)[%c(SBSoundController) sharedInstance] _playSystemSound:sound];

		// Clean up
		[vibrationPatternArray release];
		[vibrationPatternDict release];
		[sound release];

}

-(void)biometricEventMonitor: (id)monitor handleBiometricEvent: (unsigned)event
{

	if (event == 1)
		[self vibrate];

	// event 2 finger held, event 4 finger matched, 10 not matched
	if (event == 1 || event == 2 || event == 4 || event == 10)
		[[%c(SBBacklightController) sharedInstance] turnOnScreenFullyWithBacklightSource:0];

}

-(void)startMonitoringEvents
{
	id monitor = [%c(SBUIBiometricEventMonitor) sharedInstance];
	[[%c(BiometricKit) manager] setDelegate:monitor];
	[monitor addObserver:self];
	[monitor _setMatchingEnabled:YES];
	[monitor _startMatching];
}

@end

%ctor
{
   TouchUnlockController *unlockController = [[TouchUnlockController alloc] init];
   [unlockController startMonitoringEvents];
}

/*
        NSString *msg = [NSString stringWithFormat:@"Number of Tap : %llu", currentNumTap];
	NSString *title = @"title";
	NSString *cancel = @"OK";
	UIAlertView *a = [[UIAlertView alloc] initWithTitle:title
        message:msg delegate:nil cancelButtonTitle:cancel otherButtonTitles:nil];
        [a show];
        [a release];
*/
