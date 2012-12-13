//
//  NSObject+RACBindings.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/4/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACBindings.h"
#import "NSObject+RACKVOWrapper.h"
#import "EXTScope.h"
#import "RACDisposable.h"
#import "RACScheduler.h"
#import "RACSubject.h"

@implementation NSObject (RACBindings)

- (RACDisposable *)rac_bind:(NSString *)receiverKeyPath signalBlock:(RACSignalTransformationBlock)receiverSignalBlock toObject:(id)otherObject withKeyPath:(NSString *)otherKeyPath signalBlock:(RACSignalTransformationBlock)otherSignalBlock {
	@weakify(self);
	@weakify(otherObject);
	
	RACSubject *receiverSubject = [RACSubject subject];
	RACSubject *otherObjectSubject = [RACSubject subject];
	
	NSObject *countersLock = [[NSObject alloc] init];
	__block NSUInteger receiverVersion = 0;
	__block NSUInteger otherObjectVersion = 0;
	__block BOOL receiverExpectedBounces = NO;
	__block BOOL otherObjectExpectedBounces = NO;
	
	RACDisposable *receiverDisposable = [(receiverSignalBlock ? receiverSignalBlock(receiverSubject) : receiverSubject) subscribeNext:^(id x) {
		@synchronized (countersLock) {
			@strongify(otherObject);
			otherObjectExpectedBounces = YES;
			[otherObject setValue:x forKeyPath:otherKeyPath];
		}
	}];
	
	RACDisposable *otherObjectDisposable = [(otherSignalBlock ? otherSignalBlock(otherObjectSubject) : otherObjectSubject) subscribeNext:^(id x) {
		@synchronized (countersLock) {
			@strongify(self);
			receiverExpectedBounces = YES;
			[self setValue:x forKeyPath:receiverKeyPath];
		}
	}];
	
	id receiverObserverIdentifier = [self rac_addObserver:otherObject forKeyPath:receiverKeyPath options:0 queue:nil block:^(id observer, NSDictionary *change) {
		id value;
		
		@synchronized (countersLock) {
			BOOL shouldSend = receiverVersion - otherObjectVersion < UINT32_MAX / 2;
			if (receiverExpectedBounces) {
				receiverExpectedBounces = NO;
				receiverVersion += 1;
			}
			
			if (!shouldSend) return;
			receiverVersion += 1;
			
			@strongify(self);
			value = [self valueForKeyPath:receiverKeyPath];
		}
		
		[receiverSubject sendNext:value];
	}];
	
	id otherObjectObserverIdentifier = [otherObject rac_addObserver:self forKeyPath:otherKeyPath options:NSKeyValueObservingOptionInitial queue:nil block:^(id observer, NSDictionary *change) {
		id value;
		
		@synchronized (countersLock) {
			BOOL shouldSend = otherObjectVersion - receiverVersion < UINT32_MAX / 2;
			if (otherObjectExpectedBounces) {
				otherObjectExpectedBounces = NO;
				otherObjectVersion += 1;
			}
			
			if (!shouldSend) return;
			otherObjectVersion += 1;
			
			@strongify(otherObject);
			value = [otherObject valueForKeyPath:otherKeyPath];
		}
		
		[otherObjectSubject sendNext:value];
	}];
	
	return [RACDisposable disposableWithBlock:^{
		[receiverDisposable dispose];
		[otherObjectDisposable dispose];
		[self rac_removeObserverWithIdentifier:receiverObserverIdentifier];
		[otherObject rac_removeObserverWithIdentifier:otherObjectObserverIdentifier];
	}];
}

@end
