//
//  main.m
//  Test
//
//  Created by Uri Baghin on 08/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

@interface CountUpToXEnumerator : NSEnumerator

+ (instancetype)countUpTo:(NSUInteger)x;

@end

@implementation CountUpToXEnumerator {
	NSUInteger _x;
	NSUInteger _current;
}

+ (instancetype)countUpTo:(NSUInteger)x {
	CountUpToXEnumerator *enumerator = [[self alloc] init];
	enumerator->_x = x;
	return enumerator;
}

- (id)nextObject {
	if (_current == _x) return nil;
	return @(_current++);
}

@end

int main(int argc, const char * argv[]) {
	
	@autoreleasepool {
		
		NSEnumerator *enumerator = [CountUpToXEnumerator countUpTo:100000];
		
		@autoreleasepool {
			enumerator = [[enumerator.rac_sequence map:^id(id value) {
				return value;
			}] filter:^BOOL(id value) {
				return YES;
			}].objectEnumerator;
		}
		
		NSUInteger sum = 0;
//		for (NSNumber *x in enumerator) {
//			sum += x.unsignedIntegerValue;
//		}
		
		for (;;) {
			@autoreleasepool {
				NSNumber *x __attribute__((objc_precise_lifetime)) = [enumerator nextObject];
				if (x == nil) break;
				sum += x.unsignedIntegerValue;
			}
		}

	}
	
	return 0;
}

