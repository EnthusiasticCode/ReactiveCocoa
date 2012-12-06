//
//  NSObject+RACBindings.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/4/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACBindings.h"
#import "RACSignal.h"
#import "NSObject+RACKVOWrapper.h"
#import "RACSubject.h"
#import "RACDisposable.h"
#import "RACScheduler.h"

@interface RACBindingVersion : NSObject
@property (nonatomic) uint32_t receiverVersion;
@property (nonatomic) uint32_t otherObjectVersion;
@property (nonatomic) uint32_t receiverExpectedBounces;
@property (nonatomic) uint32_t otherObjectExpectedBounces;

- (BOOL)checkReceiverForSendAndUpdate;
- (BOOL)checkOtherObjectForSendAndUpdate;
- (void)receiverReceivedUpdate;
- (void)otherObjectReceivedUpdate;
@end

@implementation RACBindingVersion
- (BOOL)checkReceiverForSendAndUpdate {
	BOOL shouldSend = self.receiverVersion >= self.otherObjectVersion;
	if (shouldSend) {
		self.receiverVersion += 1;
	}
	if (self.receiverExpectedBounces > 0) {
		self.receiverVersion += 1;
		self.receiverExpectedBounces -= 1;
	}
	return shouldSend;
}

- (BOOL)checkOtherObjectForSendAndUpdate {
	BOOL shouldSend = self.otherObjectVersion >= self.receiverVersion;
	if (shouldSend) {
		self.otherObjectVersion += 1;
	}
	if (self.otherObjectExpectedBounces > 0) {
		self.otherObjectVersion += 1;
		self.otherObjectExpectedBounces -= 1;
	}
	return shouldSend;
}

- (void)receiverReceivedUpdate {
	self.receiverExpectedBounces += 1;
}

- (void)otherObjectReceivedUpdate {
	self.otherObjectExpectedBounces += 1;
}
@end

@implementation NSObject (RACBindings)

- (RACDisposable *)rac_bind:(NSString *)receiverKeyPath signalBlock:(RACSignalTransformationBlock)receiverSignalBlock toObject:(id)otherObject withKeyPath:(NSString *)otherKeyPath signalBlock:(RACSignalTransformationBlock)otherSignalBlock {
	
	// TODO: This implementation is a draft, requires polishing, retain cycle fixing and more
	
	RACSubject *receiverSubject = [RACSubject subject];
	RACSubject *otherObjectSubject = [RACSubject subject];
	
	RACBindingVersion *version = [[RACBindingVersion alloc] init];
	
	RACDisposable *otherObjectDisposable = [(otherSignalBlock ? otherSignalBlock(receiverSubject) : receiverSubject) subscribeNext:^(id x) {
		@synchronized (version) {
			[version otherObjectReceivedUpdate];
			[otherObject setValue:x forKey:otherKeyPath];
		}
	}];
	
	id receiverObserverIdentifier = [self rac_addObserver:otherObject forKeyPath:receiverKeyPath options:0 queue:nil block:^(id observer, NSDictionary *change) {
		@synchronized (version) {
			if (version.checkReceiverForSendAndUpdate) {
				[receiverSubject sendNext:[self valueForKey:receiverKeyPath]];
			}
		}
	}];
	
	RACDisposable *receiverDisposable = [(receiverSignalBlock ? receiverSignalBlock(otherObjectSubject) : otherObjectSubject) subscribeNext:^(id x) {
		@synchronized (version) {
			[version receiverReceivedUpdate];
			[self setValue:x forKey:receiverKeyPath];
		}
	}];
	
	id otherObjectObserverIdentifier = [otherObject rac_addObserver:self forKeyPath:otherKeyPath options:NSKeyValueObservingOptionInitial queue:nil block:^(id observer, NSDictionary *change) {
		@synchronized (version) {
			if (version.checkOtherObjectForSendAndUpdate) {
				[otherObjectSubject sendNext:[otherObject valueForKey:otherKeyPath]];
			}
		}
	}];
	
	return [RACDisposable disposableWithBlock:^{
		[otherObject rac_removeObserverWithIdentifier:otherObjectObserverIdentifier];
		[receiverDisposable dispose];
		[self rac_removeObserverWithIdentifier:receiverObserverIdentifier];
		[otherObjectDisposable dispose];
	}];
}

- (RACDisposable *)rac_bind:(NSString *)receiverKeyPath transformer:(id (^)(id))receiverTransformer onScheduler:(RACScheduler *)receiverScheduler toObject:(id)otherObject withKeyPath:(NSString *)otherKeyPath transformer:(id (^)(id))otherTransformer onScheduler:(RACScheduler *)otherScheduler {
	static id (^nilPlaceHolder)(void) = ^{
		static id nilPlaceHolder = nil;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			nilPlaceHolder = [[NSObject alloc] init];
		});
		return nilPlaceHolder;
	};
	
	if (receiverScheduler == nil) receiverScheduler = RACScheduler.immediateScheduler;
	if (otherScheduler == nil) otherScheduler = RACScheduler.immediateScheduler;
	
	NSMutableArray *receiverBounces = NSMutableArray.array;
	NSMutableArray *otherBounces = NSMutableArray.array;
	
	__block volatile uint32_t versionCounter = 0;
	__block uint32_t receiverVersionLowerBound = 0;
	__block uint32_t otherVersionLowerBound = 0;
	__block volatile uint32_t *versionCounterPtr = &versionCounter;
	__block uint32_t *receiverVersionLowerBoundPtr = &receiverVersionLowerBound;
	__block uint32_t *otherVersionLowerBoundPtr = &otherVersionLowerBound;
	
	static id (^addAsObserver)(id, id, NSString *, NSMutableArray *, uint32_t *, id(^)(id), id, NSString *, NSMutableArray *, uint32_t *, RACScheduler *, volatile uint32_t *, NSKeyValueObservingOptions) = ^(id observer, id target, NSString *targetKeyPath, NSMutableArray *targetBounces, uint32_t *targetVersionLowerBound, id(^targetTransformer)(id), id boundObject, NSString *boundObjectKeyPath, NSMutableArray *boundObjectBounces, uint32_t *boundObjectVersionLowerBound, RACScheduler *boundObjectScheduler, volatile uint32_t *versionCounter, NSKeyValueObservingOptions options){
		return [target rac_addObserver:observer forKeyPath:targetKeyPath options:options queue:nil block:^(id observer, NSDictionary *change) {
			uint32_t currentVersion = __sync_fetch_and_add(versionCounter, 1);
			*targetVersionLowerBound = currentVersion;
			id value = [target valueForKeyPath:targetKeyPath];
			
			@synchronized(targetBounces) {
				for (NSUInteger i = 0; i < targetBounces.count; ++i) {
					if ([targetBounces[i] isEqual:(value == nil ? nilPlaceHolder() : value)]) {
						[targetBounces removeObjectAtIndex:i];
						return;
					}
				}
			}
			
			if (targetTransformer != nil) value = targetTransformer(value);
			
			[boundObjectScheduler schedule:^{
				if (currentVersion - *boundObjectVersionLowerBound > UINT32_MAX / 2) return;
				@synchronized(boundObjectBounces) {
					[boundObjectBounces addObject:(value == nil ? nilPlaceHolder() : value)];
				}
				[boundObject setValue:value forKeyPath:boundObjectKeyPath];
			}];
		}];
	};
	
	id outgoingIdentifier = addAsObserver(self, self, receiverKeyPath, receiverBounces, receiverVersionLowerBoundPtr, receiverTransformer, otherObject, otherKeyPath, otherBounces, otherVersionLowerBoundPtr, otherScheduler, versionCounterPtr, 0);
	id incomingIdentifier = addAsObserver(self, otherObject, otherKeyPath, otherBounces, otherVersionLowerBoundPtr, otherTransformer, self, receiverKeyPath, receiverBounces, receiverVersionLowerBoundPtr, receiverScheduler, versionCounterPtr, NSKeyValueObservingOptionInitial);
		
	return [RACDisposable disposableWithBlock:^{
		[self rac_removeObserverWithIdentifier:outgoingIdentifier];
		[otherObject rac_removeObserverWithIdentifier:incomingIdentifier];
	}];
}

@end
