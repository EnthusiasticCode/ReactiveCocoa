//
//  NSObject+RACBindings.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/4/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACBindings.h"
#import "NSObject+RACKVOWrapper.h"
#import "RACDisposable.h"
#import "RACScheduler.h"


@implementation NSObject (RACBindings)

// bind target to observer: target -x-> targetTransformer(x) -observerScheduler-> observer
//static id RACBindingAddAsObserver(id target, NSString *targetKeyPath, id(^targetTransformer)(id), id observer, NSString *observerKeyPath, RACScheduler *observerScheduler, id counterLockObject, uint32_t *targetVersion, uint32_t *targetExpectedBounces, uint32_t *observerVersion, uint32_t *observerExpectedBounces, NSKeyValueObservingOptions observingOptions) {
//	return [target rac_addObserver:observer forKeyPath:targetKeyPath options:observingOptions queue:nil block:^(id observer, NSDictionary *change) {
//		id value;
//		
//		@synchronized (counterLockObject) {
//			BOOL shouldSend = *targetVersion >= *observerVersion;
//			if (*targetExpectedBounces > 0) {
//				*targetExpectedBounces -= 1;
//				*targetVersion += 1;
//			}
//			
//			if (!shouldSend) return;
//			*targetVersion += 1;
//			
//			value = [target valueForKeyPath:targetKeyPath];
//			if (targetTransformer != nil) value = targetTransformer(value);
//		}
//		
//		[observerScheduler schedule:^{
//			@synchronized (counterLockObject) {
//				*observerExpectedBounces += 1;
//				[observer setValue:value forKeyPath:observerKeyPath];
//			}
//		}];
//	}];
//}

- (RACDisposable *)rac_bind:(NSString *)receiverKeyPath transformer:(id (^)(id))receiverTransformer onScheduler:(RACScheduler *)receiverScheduler toObject:(id)otherObject withKeyPath:(NSString *)otherKeyPath transformer:(id (^)(id))otherTransformer onScheduler:(RACScheduler *)otherScheduler {
	if (receiverScheduler == nil) receiverScheduler = RACScheduler.immediateScheduler;
	if (otherScheduler == nil) otherScheduler = RACScheduler.immediateScheduler;
	
	NSObject *countersLock = [[NSObject alloc] init];
	__block uint32_t receiverVersion = 0;
	__block uint32_t otherObjectVersion = 0;
	__block uint32_t receiverExpectedBounces = 0;
	__block uint32_t otherObjectExpectedBounces = 0;
	
//	id receiverObserverIdentifier = RACBindingAddAsObserver(self, receiverKeyPath, receiverTransformer, otherObject, otherKeyPath, otherScheduler, countersLock, &receiverVersion, &receiverExpectedBounces, &otherObjectVersion, &otherObjectExpectedBounces, 0);
//	id otherObjectObserverIdentifier = RACBindingAddAsObserver(otherObject, otherKeyPath, otherTransformer, self, receiverKeyPath, receiverScheduler, countersLock, &otherObjectVersion, &otherObjectExpectedBounces, &receiverVersion, &receiverExpectedBounces, NSKeyValueObservingOptionInitial);

	id receiverObserverIdentifier = [self rac_addObserver:otherObject forKeyPath:receiverKeyPath options:0 queue:nil block:^(id observer, NSDictionary *change) {
		id value;
		
		@synchronized (countersLock) {
			BOOL shouldSend = receiverVersion >= otherObjectVersion;
			if (receiverExpectedBounces > 0) {
				receiverExpectedBounces -= 1;
				receiverVersion += 1;
			}
			
			if (!shouldSend) return;
			receiverVersion += 1;
			value = [self valueForKeyPath:receiverKeyPath];
		}
		
		if (receiverTransformer != nil) value = receiverTransformer(value);
		
		[otherScheduler schedule:^{
			@synchronized (countersLock) {
				otherObjectExpectedBounces += 1;
				[otherObject setValue:value forKeyPath:otherKeyPath];
			}
		}];
	}];
	
	id otherObjectObserverIdentifier = [otherObject rac_addObserver:self forKeyPath:otherKeyPath options:NSKeyValueObservingOptionInitial queue:nil block:^(id observer, NSDictionary *change) {
		id value;
		
		@synchronized (countersLock) {
			BOOL shouldSend = otherObjectVersion >= receiverVersion;
			if (otherObjectExpectedBounces > 0) {
				otherObjectExpectedBounces -= 1;
				otherObjectVersion += 1;
			}
			
			if (!shouldSend) return;
			otherObjectVersion += 1;
			value = [otherObject valueForKeyPath:otherKeyPath];
		}
		
		if (otherTransformer != nil) value = otherTransformer(value);
		
		[receiverScheduler schedule:^{
			@synchronized (countersLock) {
				receiverExpectedBounces += 1;
				[self setValue:value forKeyPath:receiverKeyPath];
			}
		}];
	}];
	
	return [RACDisposable disposableWithBlock:^{
		[self rac_removeObserverWithIdentifier:receiverObserverIdentifier];
		[otherObject rac_removeObserverWithIdentifier:otherObjectObserverIdentifier];
	}];
}

@end
