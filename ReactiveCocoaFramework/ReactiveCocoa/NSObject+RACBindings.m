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
	
	__block volatile int32_t receiverIgnoreFlag = 0;
	__block volatile int32_t otherObjectIgnoreFlag = 0;
	
	if (receiverSignalBlock == NULL) receiverSignalBlock = RACSignalTransformationIdentity;
	if (otherSignalBlock == NULL) otherSignalBlock = RACSignalTransformationIdentity;
	
	RACDisposable *receiverDisposable = [otherSignalBlock(receiverSubject) subscribeNext:^(id x) {
		@strongify(otherObject);
		[otherObject setValue:x forKey:otherKeyPath];
		OSAtomicDecrement32(&otherObjectIgnoreFlag);
	}];
	
	RACDisposable *otherDisposable = [receiverSignalBlock(otherSubject) subscribeNext:^(id x) {
		@strongify(self);
		[self setValue:x forKey:receiverKeyPath];
		OSAtomicDecrement32(&receiverIgnoreFlag);
	}];
	
	id receiverObserver = [self rac_addObserver:otherObject forKeyPath:receiverKeyPath options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew queue:[NSOperationQueue mainQueue] block:^(id observer, NSDictionary *change) {
		if (receiverIgnoreFlag > 0) return;
		
		NSNumber *isPrior = change[NSKeyValueChangeNotificationIsPriorKey];
		if (isPrior.boolValue) {
			OSAtomicIncrement32(&otherObjectIgnoreFlag);
			return;
		}
		
		id value = change[NSKeyValueChangeNewKey];
		if (value) {
			[receiverSubject sendNext:(value == [NSNull null] ? nil : value)];
		}
	}];
	
	id otherObjectObserver = [otherObject rac_addObserver:self forKeyPath:otherKeyPath options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial queue:[NSOperationQueue mainQueue] block:^(id observer, NSDictionary *change) {
		if (otherObjectIgnoreFlag > 0) return;
		
		NSNumber *isPrior = change[NSKeyValueChangeNotificationIsPriorKey];
		if (isPrior.boolValue) {
			OSAtomicIncrement32(&receiverIgnoreFlag);
			return;
		}
		
		id value = change[NSKeyValueChangeNewKey];
		if (value) {
			[otherSubject sendNext:(value == [NSNull null] ? nil : value)];
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
