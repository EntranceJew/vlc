/*****************************************************************************
 * VLCSliderCell.m
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 *
 * Authors: Marvin Scholz <epirat07 at gmail dot com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCSliderCell.h"

#import <CoreVideo/CoreVideo.h>

#import "extensions/NSGradient+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "main/CompatibilityFixes.h"

@interface VLCSliderCell () {
    NSInteger _animationPosition;
    double _lastTime;
    double _deltaToLastFrame;
    CVDisplayLinkRef _displayLink;

    NSColor *_emptySliderBackgroundColor;
}
@end

@implementation VLCSliderCell

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setSliderStyleLight];
        self.animationWidth = self.controlView.bounds.size.width;

        [self initDisplayLink];
    }
    return self;
}

- (void)setSliderStyleLight
{
    _emptySliderBackgroundColor = NSColor.VLCSliderLightBackgroundColor;
}

- (void)setSliderStyleDark
{
    _emptySliderBackgroundColor = NSColor.VLCSliderDarkBackgroundColor;
}

- (void)dealloc
{
    CVDisplayLinkRelease(_displayLink);
}

static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, 
                                    const CVTimeStamp *inNow,
                                    const CVTimeStamp *inOutputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *displayLinkContext)
{
    const CVTimeStamp inNowCopy = *inNow;
    dispatch_async(dispatch_get_main_queue(), ^{
        VLCSliderCell * const sliderCell = (__bridge VLCSliderCell*)displayLinkContext;
        [sliderCell displayLink:displayLink tickWithTime:&inNowCopy];
    });
    return kCVReturnSuccess;
}

- (void)displayLink:(CVDisplayLinkRef)displayLink tickWithTime:(const CVTimeStamp*)inNow
{
    if (_lastTime == 0) {
        _deltaToLastFrame = 0;
    } else {
        _deltaToLastFrame = (double)(inNow->videoTime - _lastTime) / inNow->videoTimeScale;
    }
    _lastTime = inNow->videoTime;

    self.controlView.needsDisplay = YES;
}

- (void)initDisplayLink
{
    const CVReturn ret = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (ret != kCVReturnSuccess) {
        // TODO: Handle error
        return;
    }
    CVDisplayLinkSetOutputCallback(_displayLink, DisplayLinkCallback, (__bridge void*) self);
}

#pragma mark -
#pragma mark Normal slider drawing

- (void)drawKnob:(NSRect)knobRect
{
    if (self.knobHidden) {
        return;
    }

    [super drawKnob:knobRect];
}

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    static const CGFloat trackBorderRadius = 1;

    // Empty Track Drawing
    NSBezierPath * const emptyTrackPath =
        [NSBezierPath bezierPathWithRoundedRect:rect
                                        xRadius:trackBorderRadius
                                        yRadius:trackBorderRadius];
    [_emptySliderBackgroundColor setFill];
    [emptyTrackPath fill];

    if (self.knobHidden) {
        return;
    }

    // Calculate filled track
    NSRect filledTrackRect = rect;
    const NSRect knobRect = [self knobRectFlipped:NO];
    filledTrackRect.size.width = knobRect.origin.x + (knobRect.size.width / 2);

    // Filled Track Drawing
    NSBezierPath * const filledTrackPath = 
        [NSBezierPath bezierPathWithRoundedRect:filledTrackRect
                                        xRadius:trackBorderRadius
                                        yRadius:trackBorderRadius];

    [NSColor.VLCAccentColor setFill];
    [filledTrackPath fill];
}

#pragma mark -
#pragma mark Indefinite slider drawing


- (void)drawHighlightInRect:(NSRect)rect
{
    [self.highlightGradient drawInRect:rect angle:0];
}


- (void)drawHighlightBackgroundInRect:(NSRect)rect
{
    rect = NSInsetRect(rect, 1.0, 1.0);
    NSBezierPath * const fullPath =
        [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0];
    [self.highlightBackground setFill];
    [fullPath fill];
}

- (void)drawAnimationInRect:(NSRect)rect
{
    [self drawHighlightBackgroundInRect:rect];

    [NSGraphicsContext saveGraphicsState];
    rect = NSInsetRect(rect, 1.0, 1.0);
    NSBezierPath * const fullPath =
        [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0];
    [fullPath setClip];

    // Use previously calculated position
    rect.origin.x = _animationPosition;

    // Calculate new position for next Frame
    if (_animationPosition < (rect.size.width + _animationWidth)) {
        _animationPosition += (rect.size.width + _animationWidth) * _deltaToLastFrame;
    } else {
        _animationPosition = -(_animationWidth);
    }

    rect.size.width = _animationWidth;

    [self drawHighlightInRect:rect];
    [NSGraphicsContext restoreGraphicsState];
    _deltaToLastFrame = 0;
}


- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if (self.indefinite) {
        return [self drawAnimationInRect:cellFrame];
    }

    [super drawWithFrame:cellFrame inView:controlView];

}

#pragma mark -
#pragma mark Animation handling

- (void)beginAnimating
{
    const CVReturn err = CVDisplayLinkStart(_displayLink);
    if (err != kCVReturnSuccess) {
        // TODO: Handle error
    }
    _animationPosition = -(_animationWidth);
    self.enabled = NO;
}

- (void)endAnimating
{
    CVDisplayLinkStop(_displayLink);
    self.enabled = YES;

}

- (void)setIndefinite:(BOOL)indefinite
{
    if (self.indefinite == indefinite) {
        return;
    }

    _indefinite = indefinite;

    if (indefinite) {
        [self beginAnimating];
    } else {
        [self endAnimating];
    }
}

- (void)setKnobHidden:(BOOL)knobHidden
{
    _knobHidden = knobHidden;
    self.controlView.needsDisplay = YES;
}


@end
