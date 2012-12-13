//
//  NSObjectRACBindingsSpec.m
//  ReactiveCocoa
//
//  Created by Uri Baghin on 03/12/2012.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACBindings.h"
#import "EXTKeyPathCoding.h"
#import "RACSignal.h"
#import "RACDisposable.h"
#import "NSObject+RACKVOWrapper.h"
#import "RACScheduler+Private.h"
#import <pthread.h>
#import <mach/thread_act.h>

kern_return_t	thread_policy_set(thread_t thread, thread_policy_flavor_t flavor, thread_policy_t policy_info, mach_msg_type_number_t count);
kern_return_t	thread_policy_get(thread_t thread, thread_policy_flavor_t flavor, thread_policy_t policy_info, mach_msg_type_number_t	*count, boolean_t *get_default);


@interface RACRacingSchedulerData : NSObject

@property (nonatomic) pthread_t thread;
@property (nonatomic, strong) NSMutableArray *blockQueue;
@property (nonatomic) BOOL shouldStop;

@end

@implementation RACRacingSchedulerData
@end

@interface RACRacingScheduler : RACScheduler

@end

static integer_t RACRacingSchedulerNewTag(void) {
	static integer_t tag = 0;
	return ++tag;
}

static void *RACRacingSchedulerStartRoutine(void *arg) {
	@autoreleasepool {
		RACRacingSchedulerData *data = CFBridgingRelease(arg);
		for (;;) {
			dispatch_block_t block = nil;
			@synchronized(data) {
				block = data.blockQueue.lastObject;
				[data.blockQueue removeLastObject];
			}
			if (block != nil) {
				block();
			}
			@synchronized(data) {
				if (data.shouldStop) break;
			}
			sleep(0);
		}
	}
	return NULL;
}

@implementation RACRacingScheduler {
	RACRacingSchedulerData *_data;
}

- (instancetype)initWithName:(NSString *)name {
	self = [super initWithName:name];
	if (self == nil) return nil;
	
	_data = [[RACRacingSchedulerData alloc] init];
	if (_data == nil) return nil;
	_data.blockQueue = [NSMutableArray array];
	
	pthread_t thread;
	if(pthread_create_suspended_np(&thread, NULL, RACRacingSchedulerStartRoutine, (void*)CFBridgingRetain(_data)) != 0) return nil;
	mach_port_t mach_thread = pthread_mach_thread_np(thread);
	thread_affinity_policy_data_t policyData = { RACRacingSchedulerNewTag() };
	thread_policy_set(mach_thread, THREAD_AFFINITY_POLICY, (thread_policy_t)&policyData, 1);
	thread_resume(mach_thread);
	
	return self;
}

- (void)dealloc {
	@synchronized(_data) {
		_data.shouldStop = YES;
	}
}

- (void)schedule:(void (^)(void))block {
	NSParameterAssert(block != nil);
	@synchronized(_data) {
		[_data.blockQueue insertObject:[block copy] atIndex:0];
	}
}

@end

@interface TestClass : NSObject
@property (nonatomic, strong) NSString *name;
@end

@implementation TestClass
@end

SpecBegin(NSObjectRACBindings)

describe(@"-rac_bind:signalBlock:toObject:withKeyPath:signalBlock:", ^{
	__block TestClass *a;
	__block TestClass *b;
	__block TestClass *c;
	__block NSString *testName1;
	__block NSString *testName2;
	__block NSString *testName3;
	
	before(^{
		a = [[TestClass alloc] init];
		b = [[TestClass alloc] init];
		c = [[TestClass alloc] init];
		testName1 = @"sync it!";
		testName2 = @"sync it again!";
		testName3 = @"sync it once more!";
	});
	
	it(@"should keep objects' properties in sync", ^{
		[a rac_bind:@keypath(a.name) signalBlock:nil toObject:b withKeyPath:@keypath(b.name) signalBlock:nil];
		expect(a.name).to.beNil();
		expect(b.name).to.beNil();
		a.name = testName1;
		expect(a.name).to.equal(testName1);
		expect(b.name).to.equal(testName1);
		b.name = testName2;
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
		a.name = nil;
		expect(a.name).to.beNil();
		expect(b.name).to.beNil();
	});
	
	it(@"should take the master's value at the start", ^{
		a.name = testName1;
		b.name = testName2;
		[a rac_bind:@keypath(a.name) signalBlock:nil toObject:b withKeyPath:@keypath(b.name) signalBlock:nil];
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
	});
	
	it(@"should bind transitively", ^{
		a.name = testName1;
		b.name = testName2;
		c.name = testName3;
		[a rac_bind:@keypath(a.name) signalBlock:nil toObject:b withKeyPath:@keypath(b.name) signalBlock:nil];
		[b rac_bind:@keypath(b.name) signalBlock:nil toObject:c withKeyPath:@keypath(c.name) signalBlock:nil];
		expect(a.name).to.equal(testName3);
		expect(b.name).to.equal(testName3);
		expect(c.name).to.equal(testName3);
		c.name = testName1;
		expect(a.name).to.equal(testName1);
		expect(b.name).to.equal(testName1);
		expect(c.name).to.equal(testName1);
		b.name = testName2;
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
		expect(c.name).to.equal(testName2);
		a.name = testName3;
		expect(a.name).to.equal(testName3);
		expect(b.name).to.equal(testName3);
		expect(c.name).to.equal(testName3);
	});
	
	it(@"should bind even if the initial update is the same as the other object's value", ^{
		a.name = testName1;
		b.name = testName2;
		[a rac_bind:@keypath(a.name) signalBlock:nil toObject:b withKeyPath:@keypath(b.name) signalBlock:nil];
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
		b.name = testName2;
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
	});
	
	it(@"should bind even if the initial update is the same as the receiver's value", ^{
		a.name = testName1;
		b.name = testName2;
		[a rac_bind:@keypath(a.name) signalBlock:nil toObject:b withKeyPath:@keypath(b.name) signalBlock:nil];
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
		b.name = testName1;
		expect(a.name).to.equal(testName1);
		expect(b.name).to.equal(testName1);
	});
	
	it(@"should not interfere with other KVO callbacks", ^{
		__block BOOL firstObserverShouldChangeName = YES;
		__block BOOL secondObserverShouldChangeName = YES;
		__block BOOL thirdObserverShouldChangeName = YES;
		__block BOOL fourthObserverShouldChangeName = YES;
		__block BOOL observerIsSettingValue = NO;
		[a rac_addObserver:self forKeyPath:@keypath(a.name) options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew queue:nil block:^(id observer, NSDictionary *change) {
			if (observerIsSettingValue) return;
			if (firstObserverShouldChangeName) {
				firstObserverShouldChangeName = NO;
				observerIsSettingValue = YES;
				a.name = testName1;
				observerIsSettingValue = NO;
			}
		}];
		[a rac_addObserver:self forKeyPath:@keypath(a.name) options:NSKeyValueObservingOptionOld queue:nil block:^(id observer, NSDictionary *change) {
			if (observerIsSettingValue) return;
			if (secondObserverShouldChangeName) {
				secondObserverShouldChangeName = NO;
				observerIsSettingValue = YES;
				a.name = testName2;
				observerIsSettingValue = NO;
			}
		}];
		[a rac_bind:@keypath(a.name) signalBlock:nil toObject:b withKeyPath:@keypath(b.name) signalBlock:nil];
		[a rac_addObserver:self forKeyPath:@keypath(a.name) options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew queue:nil block:^(id observer, NSDictionary *change) {
			if (observerIsSettingValue) return;
			if (thirdObserverShouldChangeName) {
				thirdObserverShouldChangeName = NO;
				observerIsSettingValue = YES;
				a.name = testName1;
				observerIsSettingValue = NO;
			}
		}];
		[a rac_addObserver:self forKeyPath:@keypath(a.name) options:NSKeyValueObservingOptionOld queue:nil block:^(id observer, NSDictionary *change) {
			if (observerIsSettingValue) return;
			if (fourthObserverShouldChangeName) {
				fourthObserverShouldChangeName = NO;
				observerIsSettingValue = YES;
				a.name = testName2;
				observerIsSettingValue = NO;
			}
		}];
		a.name = testName3;
		expect(firstObserverShouldChangeName).to.beFalsy();
		expect(secondObserverShouldChangeName).to.beFalsy();
		expect(thirdObserverShouldChangeName).to.beFalsy();
		expect(fourthObserverShouldChangeName).to.beFalsy();
		expect(a.name).to.equal(testName2);
		expect(b.name).to.equal(testName2);
	});
	
	it(@"should trasform values of bound properties", ^{
		[a rac_bind:@keypath(a.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal map:^id(id value) {
				return [NSString stringWithFormat:@"%@.%@", value, c.name];
			}];
		} toObject:b withKeyPath:@keypath(b.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal map:^id(id value) {
				return [value stringByDeletingPathExtension];
			}];
		}];
		[c rac_bind:@keypath(c.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal map:^id(id value) {
				return [NSString stringWithFormat:@"%@.%@", a.name, value];
			}];
		} toObject:b withKeyPath:@keypath(b.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal map:^id(id value) {
				return [value pathExtension];
			}];
		}];
		expect(a.name).to.beNil();
		expect(b.name).to.beNil();
		expect(c.name).to.beNil();
		b.name = @"file.txt";
		expect(a.name).to.equal(@"file");
		expect(b.name).to.equal(@"file.txt");
		expect(c.name).to.equal(@"txt");
		a.name = @"file2";
		expect(a.name).to.equal(@"file2");
		expect(b.name).to.equal(@"file2.txt");
		expect(c.name).to.equal(@"txt");
		c.name = @"rtf";
		expect(a.name).to.equal(@"file2");
		expect(b.name).to.equal(@"file2.rtf");
		expect(c.name).to.equal(@"rtf");
	});
	
	it(@"should run transformations only once per change, and only in one direction", ^{
		__block NSUInteger aCounter = 0;
		__block NSUInteger cCounter = 0;
		id<RACSignal> (^incrementACounter)(id<RACSignal>) = ^(id<RACSignal> signal) {
			return [signal doNext:^(id x) {
				++aCounter;
			}];
		};
		id<RACSignal> (^incrementCCounter)(id<RACSignal>) = ^(id<RACSignal> signal) {
			return [signal doNext:^(id x) {
				++cCounter;
			}];
		};
		expect(aCounter).to.equal(0);
		expect(cCounter).to.equal(0);
		[a rac_bind:@keypath(a.name) signalBlock:incrementACounter toObject:b withKeyPath:@keypath(b.name) signalBlock:incrementACounter];
		[c rac_bind:@keypath(c.name) signalBlock:incrementCCounter toObject:b withKeyPath:@keypath(b.name) signalBlock:incrementCCounter];
		expect(aCounter).to.equal(1);
		expect(cCounter).to.equal(1);
		b.name = testName1;
		expect(aCounter).to.equal(2);
		expect(cCounter).to.equal(2);
		a.name = testName2;
		expect(aCounter).to.equal(3);
		expect(cCounter).to.equal(3);
		c.name = testName3;
		expect(aCounter).to.equal(4);
		expect(cCounter).to.equal(4);
	});
	
	it(@"should stop binding when disposed", ^{
		RACScheduler *aScheduler = [RACScheduler backgroundScheduler];
		RACScheduler *bScheduler = [RACScheduler backgroundScheduler];
		
		RACDisposable *disposable = [a rac_bind:@keypath(a.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal subscribeOn:aScheduler];
		} toObject:b withKeyPath:@keypath(b.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal subscribeOn:bScheduler];
		}];
		
		a.name = testName1;
		[disposable dispose];
		a.name = testName2;
		
		expect(a.name).will.equal(testName2);
		expect(b.name).will.equal(testName1);
	});
	
	it(@"should handle the bound objects being changed at the same time on different threads", ^{
		RACScheduler *aScheduler = [[RACRacingScheduler alloc] init];
		RACScheduler *bScheduler = [[RACRacingScheduler alloc] init];
		
		[a rac_bind:@keypath(a.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal subscribeOn:aScheduler];
		} toObject:b withKeyPath:@keypath(b.name) signalBlock:^id<RACSignal>(id<RACSignal> signal) {
			return [signal subscribeOn:bScheduler];
		}];
		
		// Race conditions aren't deterministic, so loop this test more times to catch them.
		// Change it back to 1 before committing so it's friendly on the CI testing.
		for (NSUInteger i = 0; i < 1; ++i) {
			[aScheduler schedule:^{
				a.name = nil;
			}];
			expect(a.name).will.beNil();
			expect(b.name).will.beNil();
			
			__block volatile uint32_t aReady = 0;
			__block volatile uint32_t bReady = 0;
			[aScheduler schedule:^{
				OSAtomicOr32Barrier(1, &aReady);
				while (!bReady) {
					// do nothing while waiting for b, sleeping might hide the race
				}
				a.name = testName1;
			}];
			[bScheduler schedule:^{
				OSAtomicOr32Barrier(1, &bReady);
				while (!aReady) {
					// do nothing while waiting for a, sleeping might hide the race
				}
				b.name = testName2;
			}];
			
			expect(a.name).willNot.beNil();
			expect(b.name).willNot.beNil();
			
			expect(a.name).will.equal(b.name);
		}
	});
});

SpecEnd
