//
//  JCRtmpFrameBuffer.m
//  JCLiveVideo
//
//  Created by seris-Jam on 16/6/30.
//  Copyright © 2016年 Jam. All rights reserved.
//

#import "JCRtmpFrameBuffer.h"

@interface JCRtmpFrameBuffer () {
    dispatch_semaphore_t _lock;
}

@property (nonatomic, strong) NSMutableArray *buffers;
//取样帧容器
@property (nonatomic, strong) NSMutableArray *sampleBuffers;

@end

//最大保存帧数
static const NSInteger max = 200;
//每10帧发送1帧
static const NSUInteger defaultMaxBuffers = 10;

@implementation JCRtmpFrameBuffer

- (instancetype)init {
    
    self = [super init];
    
    if (self) {
        _lock = dispatch_semaphore_create(1);
        
        self.buffers = [NSMutableArray arrayWithCapacity:max];
        self.sampleBuffers = [NSMutableArray arrayWithCapacity:defaultMaxBuffers];
    }
    
    return self;
}

- (NSInteger)getCount {
    return [self.buffers count];
}

- (void)addVideoFrame:(JCFLVVideoFrame *)videoFrame {
    [self addFrame:videoFrame];
}

- (void)addAudioFrame:(JCFLVAudioFrame *)audioFrame {
    [self addFrame:audioFrame];
}

- (void)addFrame:(id)flvFrame {
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    if (self.sampleBuffers.count < defaultMaxBuffers) {
        [self.sampleBuffers addObject:flvFrame];
    } else {
        /// 排序
        [self.sampleBuffers addObject:flvFrame];
        NSArray *sortedSendQuery = [self.sampleBuffers sortedArrayUsingFunction:frameDataCompare context:NULL];
        [self.sampleBuffers removeAllObjects];
        [self.sampleBuffers addObjectsFromArray:sortedSendQuery];
        /// 丢帧
        [self disCardVideoFrame];
        
        /// 把当前第一帧存入时间缓存中
        id frame = [self.sampleBuffers firstObject];
        if (frame) {
            [self.sampleBuffers removeObjectAtIndex:0];
            [self.buffers addObject:frame];
        }
    }
    dispatch_semaphore_signal(_lock);
}

- (id)getFirstFrame {
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    id frame = [self.buffers objectAtIndex:0];
    dispatch_semaphore_signal(_lock);
    
    if (frame) {
        [self.buffers removeObjectAtIndex:0];
        
        return frame;
    }
    
    return nil;
}

#pragma mark private

NSInteger frameDataCompare(id obj1, id obj2, void *context){
    
    if ([obj1 isKindOfClass:[JCFLVVideoFrame class]]) {
        JCFLVVideoFrame *frame1 = (JCFLVVideoFrame*) obj1;
        JCFLVVideoFrame *frame2 = (JCFLVVideoFrame*) obj2;
        
        if (frame1.timestamp == frame2.timestamp)
            return NSOrderedSame;
        else if(frame1.timestamp > frame2.timestamp)
            return NSOrderedDescending;
        return NSOrderedAscending;
    }
    
    JCFLVAudioFrame *frame1 = (JCFLVAudioFrame*) obj1;
    JCFLVAudioFrame *frame2 = (JCFLVAudioFrame*) obj2;
    
    if (frame1.timestamp == frame2.timestamp)
        return NSOrderedSame;
    else if(frame1.timestamp > frame2.timestamp)
        return NSOrderedDescending;
    return NSOrderedAscending;
    
}

//丢弃过期时间帧
- (void)disCardVideoFrame {
    if (self.buffers.count < max) {
        return ;
    }
    
    //丢弃预测帧
    NSArray *discardFrames = [self getDiscardPBFrame];
    if (discardFrames.count > 0) {
        [self.buffers removeObjectsInArray:discardFrames];
        return;
    }
    
    //如果全是关键帧，丢帧最近的关键帧
    JCFLVVideoFrame *discardIFrame = [self getFirstIFrame];
    if (discardIFrame) {
        [self.buffers removeObject:discardIFrame];
    }
    
    //如果当前buffer中全是预测帧，就全部清空
    [self.buffers removeAllObjects];
}

//获取丢弃的预测帧指的是P或者B帧
- (NSArray *)getDiscardPBFrame {
    NSMutableArray *discardFrame = [NSMutableArray array];
    
    for (id frame in self.buffers) {
        if ([frame isKindOfClass:[JCFLVVideoFrame class]]) {
            if ([(JCFLVVideoFrame *)frame isKeyFrame] && discardFrame.count > 0) {
                break;
            } else  {
                [discardFrame addObject:frame];
            }
        }
    }
    
    return discardFrame;
}

- (JCFLVVideoFrame *)getFirstIFrame {
    
    for (id iFrame in self.buffers) {
        if ([iFrame isKindOfClass:[JCFLVVideoFrame class]]) {
            if ([(JCFLVVideoFrame *)iFrame isKeyFrame]) {
                return iFrame;
            }
        }
    }
    
    return nil;
}

@end
