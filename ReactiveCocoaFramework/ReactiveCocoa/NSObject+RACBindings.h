//
//  NSObject+RACBindings.h
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/4/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RACDisposable;
@protocol RACSignal;

typedef id<RACSignal> (^RACSignalTransformationBlock)(id<RACSignal> signal);

@interface NSObject (RACBindings)

// Create a two-way binding between `receiverKeyPath` on the receiver and
// `otherKeyPath` on `otherObject`.
//
// `receiverKeyPath` on the receiver will be updated with the value of
// `otherKeyPath` on `otherObject`. After that, the two properties will be kept
// in sync by forwarding changes to one onto the other.
//
// WARNING: for this method to work, both properties must return a value equal
// to the last one that has been set, for each value that is set. This excludes
// setting `nil` on scalar properties, even if `-setNilValueForKey:` is
// overridden. In this context, a equals b if both are `nil` or if
// `[a isEqual:b]` returns `YES`.
//
// receiverKeyPath     - The key path of the receiver to bind.
// receiverSignalBlock - An optional block with which to transform values from
//                       the receiver to the binding target. Must be
//                       thread-safe.
// otherObject         - The object with which to bind the receiver.
// otherKeyPath        - The key path of the binding target to bind.
// otherSignalBlock    - An optional block with which to transform values from
//                       the binding target to the receiver. Must be
//                       thread-safe.
// 
// Returns a disposable that can be used to sever the binding.
- (RACDisposable *)rac_bind:(NSString *)receiverKeyPath signalBlock:(RACSignalTransformationBlock)receiverSignalBlock toObject:(id)otherObject withKeyPath:(NSString *)otherKeyPath signalBlock:(RACSignalTransformationBlock)otherSignalBlock;

@end
