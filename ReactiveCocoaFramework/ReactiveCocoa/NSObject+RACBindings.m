//
//  NSObject+RACBindings.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/4/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACBindings.h"
#import "RACSignal.h"
#import "RACSubject.h"
#import "NSObject+RACKVOWrapper.h"
#import "RACDisposable.h"
#import "extobjc.h"
#import <libkern/OSAtomic.h>

@implementation NSObject (RACBindings)

RACSignalTransformationBlock const RACSignalTransformationIdentity = ^(id<RACSignal> signal) {
	return signal;
};

- (RACDisposable *)rac_bind:(NSString *)receiverKeyPath signalBlock:(RACSignalTransformationBlock)receiverSignalBlock toObject:(id)otherObject withKeyPath:(NSString *)otherKeyPath signalBlock:(RACSignalTransformationBlock)otherSignalBlock {
	@weakify(self);
	@weakify(otherObject);
	
	RACSubject *receiverSubject = [RACSubject subject];
	RACSubject *otherSubject = [RACSubject subject];
	
	__block volatile uint32_t receiverBarrier = 0;
	__block volatile uint32_t otherBarrier = 0;
	
	if (receiverSignalBlock == NULL) receiverSignalBlock = RACSignalTransformationIdentity;
	if (otherSignalBlock == NULL) otherSignalBlock = RACSignalTransformationIdentity;
	
	RACDisposable *receiverDisposable = [otherSignalBlock(receiverSubject) subscribeNext:^(id x) {
		@strongify(otherObject);
		[otherObject setValue:x forKey:receiverKeyPath];
		OSAtomicAnd32(0, &otherBarrier);
	}];
	
	RACDisposable *otherDisposable = [receiverSignalBlock(otherSubject) subscribeNext:^(id x) {
		@strongify(self);
		[self setValue:x forKey:otherKeyPath];
		OSAtomicAnd32(0, &receiverBarrier);
	}];
	
	id receiverObserver = [self rac_addObserver:otherObject forKeyPath:receiverKeyPath options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew queue:[NSOperationQueue mainQueue] block:^(id observer, NSDictionary *change) {
		if (receiverBarrier > 0) return;
		
		NSNumber *isPrior = change[NSKeyValueChangeNotificationIsPriorKey];
		if (isPrior.boolValue) {
			OSAtomicOr32(1, &otherBarrier);
			return;
		}
		
		id value = change[NSKeyValueChangeNewKey];
		if (value) {
			[receiverSubject sendNext:value];
		}
	}];
	
	id otherObjectObserver = [otherObject rac_addObserver:self forKeyPath:otherKeyPath options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew queue:[NSOperationQueue mainQueue] block:^(id observer, NSDictionary *change) {
		if (otherBarrier > 0) return;
		
		NSNumber *isPrior = change[NSKeyValueChangeNotificationIsPriorKey];
		if (isPrior.boolValue) {
			OSAtomicOr32(1, &receiverBarrier);
			return;
		}
		
		id value = change[NSKeyValueChangeNewKey];
		if (value) {
			[otherSubject sendNext:value];
		}
	}];
	
	// TODO: add this disposable to self's auto-disposable pool!!!
	return [RACDisposable disposableWithBlock:^{
		@strongify(self);
		@strongify(otherObject);
		[self rac_removeObserverWithIdentifier:receiverObserver];
		[otherObject rac_removeObserverWithIdentifier:otherObjectObserver];
		
		[receiverDisposable dispose];
		[otherDisposable dispose];
	}];
}

@end
