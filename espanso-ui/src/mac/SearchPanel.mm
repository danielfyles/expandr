/*
 * This file is part of espanso.
 *
 * Copyright (C) 2019-2021 Federico Terzi
 *
 * espanso is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * espanso is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with espanso.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "SearchPanel.h"

static const CGFloat kPanelWidth = 620.0;
static const CGFloat kCornerRadius = 14.0;
static const CGFloat kInset = 20.0;        // horizontal content inset
static const CGFloat kFieldHeight = 54.0;  // search field row
static const CGFloat kSearchIconSize = 19.0;
static const CGFloat kRowHeight = 40.0;
static const NSInteger kMaxVisibleRows = 8;

// ---------------------------------------------------------------------------
// A borderless panel that can become key so its field receives keystrokes even
// though espanso is a menu-bar (accessory) app.
// ---------------------------------------------------------------------------
@interface EspansoSearchWindow : NSPanel
@end

@implementation EspansoSearchWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------
@interface EspansoSearchController
    : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate> {
@public
    NSArray<NSDictionary *> *allItems;
    NSMutableArray<NSNumber *> *filtered;
    NSPanel *window;
    NSView *contentView;
    NSImageView *searchIcon;
    NSTextField *searchField;
    NSBox *separator;
    NSTableView *tableView;
    NSScrollView *scrollView;
    int32_t result;
}
@end

@implementation EspansoSearchController

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items hint:(NSString *)hint {
    self = [super init];
    if (!self) return nil;
    allItems = items;
    filtered = [NSMutableArray array];
    result = -1;
    [self buildWindowWithHint:hint];
    [self filter:@""];
    return self;
}

- (void)buildWindowWithHint:(NSString *)hint {
    NSRect frame = NSMakeRect(0, 0, kPanelWidth, kFieldHeight);
    window = [[EspansoSearchWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.level = NSFloatingWindowLevel;
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.hasShadow = YES;
    window.releasedWhenClosed = NO;

    // Rounded, blurred background that adapts to light/dark automatically.
    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:frame];
    bg.material = NSVisualEffectMaterialHUDWindow;
    bg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bg.state = NSVisualEffectStateActive;
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = kCornerRadius;
    bg.layer.masksToBounds = YES;
    window.contentView = bg;
    contentView = bg;

    // Leading search glyph
    searchIcon = [[NSImageView alloc] init];
    if (@available(macOS 11.0, *)) {
        searchIcon.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass"
                                    accessibilityDescription:nil];
    }
    searchIcon.contentTintColor = [NSColor secondaryLabelColor];
    searchIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [bg addSubview:searchIcon];

    // Search field
    searchField = [[NSTextField alloc] init];
    searchField.font = [NSFont systemFontOfSize:20 weight:NSFontWeightRegular];
    searchField.bezeled = NO;
    searchField.bordered = NO;
    searchField.drawsBackground = NO;
    searchField.focusRingType = NSFocusRingTypeNone;
    searchField.delegate = self;
    searchField.textColor = [NSColor labelColor];
    searchField.placeholderString =
        (hint.length > 0 && hint.length <= 42) ? hint : @"Search snippets…";
    [(NSTextFieldCell *)searchField.cell setWraps:NO];
    [(NSTextFieldCell *)searchField.cell setScrollable:YES];
    [bg addSubview:searchField];
    window.initialFirstResponder = searchField;

    // Divider between field and list
    separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    [bg addSubview:separator];

    // Results table
    scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 0)];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.automaticallyAdjustsContentInsets = NO;
    scrollView.scrollerStyle = NSScrollerStyleOverlay;

    tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    tableView.headerView = nil;
    tableView.backgroundColor = [NSColor clearColor];
    tableView.rowHeight = kRowHeight;
    tableView.intercellSpacing = NSMakeSize(0, 2);
    tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    if (@available(macOS 11.0, *)) {
        tableView.style = NSTableViewStyleInset;  // rounded, inset selection
    }
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.doubleAction = @selector(tableDoubleClicked:);
    tableView.target = self;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.width = kPanelWidth;
    [tableView addTableColumn:col];
    scrollView.documentView = tableView;
    [bg addSubview:scrollView];
}

// Lay out the chrome for a given total window height (list grows below field).
- (void)layoutChrome:(CGFloat)total {
    CGFloat fieldTop = total - kFieldHeight;
    searchIcon.frame = NSMakeRect(kInset, fieldTop + (kFieldHeight - kSearchIconSize) / 2.0,
                                  kSearchIconSize, kSearchIconSize);
    CGFloat fieldX = kInset + kSearchIconSize + 12;
    CGFloat fieldH = 26;
    searchField.frame = NSMakeRect(fieldX, fieldTop + (kFieldHeight - fieldH) / 2.0,
                                   kPanelWidth - fieldX - kInset, fieldH);
    BOOL hasRows = filtered.count > 0;
    separator.frame = NSMakeRect(kInset, fieldTop, kPanelWidth - 2 * kInset, 1);
    separator.hidden = !hasRows;
    scrollView.frame = NSMakeRect(0, 0, kPanelWidth, hasRows ? fieldTop : 0);
}

// ------------------------------ filtering ---------------------------------

static NSString *stringValue(id v) {
    return [v isKindOfClass:[NSString class]] ? (NSString *)v : nil;
}

static BOOL matchesQuery(NSDictionary *item, NSString *q) {
    if (q.length == 0) return YES;
    NSMutableString *hay = [NSMutableString string];
    NSString *label = stringValue(item[@"label"]);
    NSString *trigger = stringValue(item[@"trigger"]);
    if (label) [hay appendString:label];
    if (trigger) { [hay appendString:@" "]; [hay appendString:trigger]; }
    id terms = item[@"terms"];
    if ([terms isKindOfClass:[NSArray class]]) {
        for (id t in (NSArray *)terms) {
            NSString *ts = stringValue(t);
            if (ts) { [hay appendString:@" "]; [hay appendString:ts]; }
        }
    }
    NSString *lowHay = hay.lowercaseString;
    NSString *lowQ = q.lowercaseString;
    NSUInteger hi = 0, hn = lowHay.length;
    for (NSUInteger qi = 0; qi < lowQ.length; qi++) {
        unichar qc = [lowQ characterAtIndex:qi];
        BOOL found = NO;
        while (hi < hn) {
            if ([lowHay characterAtIndex:hi++] == qc) { found = YES; break; }
        }
        if (!found) return NO;
    }
    return YES;
}

- (void)filter:(NSString *)query {
    [filtered removeAllObjects];
    for (NSUInteger i = 0; i < allItems.count; i++) {
        if (matchesQuery(allItems[i], query)) [filtered addObject:@(i)];
    }
    [tableView reloadData];
    [self resizeToFit];
    if (filtered.count > 0) {
        [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [tableView scrollRowToVisible:0];
    }
}

- (void)resizeToFit {
    NSInteger rows = MIN((NSInteger)filtered.count, kMaxVisibleRows);
    CGFloat listHeight = rows > 0 ? rows * (kRowHeight + 2) + 8 : 0;
    CGFloat total = kFieldHeight + listHeight;

    NSRect wf = window.frame;
    CGFloat dy = total - wf.size.height;   // grow from the top downwards
    wf.origin.y -= dy;
    wf.size.height = total;
    [window setFrame:wf display:YES];
    [self layoutChrome:total];
}

// --------------------------- table data/view ------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return filtered.count; }

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row { return kRowHeight; }

- (NSView *)tableView:(NSTableView *)tv
    viewForTableColumn:(NSTableColumn *)col
                   row:(NSInteger)row {
    NSDictionary *item = allItems[[filtered[row] unsignedIntegerValue]];
    NSView *cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, kRowHeight)];

    NSTextField *label = [self plainLabel:15 color:[NSColor labelColor]];
    label.stringValue = stringValue(item[@"label"]) ?: @"";

    NSString *trigger = stringValue(item[@"trigger"]);
    CGFloat rightEdge = kPanelWidth - 14;
    if (trigger.length > 0) {
        NSView *badge = [self triggerBadge:trigger];
        CGFloat bw = badge.frame.size.width;
        badge.frame = NSMakeRect(rightEdge - bw, (kRowHeight - badge.frame.size.height) / 2.0,
                                 bw, badge.frame.size.height);
        [cell addSubview:badge];
        rightEdge = badge.frame.origin.x - 10;
    }

    label.frame = NSMakeRect(14, 0, rightEdge - 14, kRowHeight);
    [cell addSubview:label];
    return cell;
}

- (NSTextField *)plainLabel:(CGFloat)size color:(NSColor *)color {
    NSTextField *f = [[NSTextField alloc] init];
    f.bezeled = NO;
    f.bordered = NO;
    f.editable = NO;
    f.selectable = NO;
    f.drawsBackground = NO;
    f.font = [NSFont systemFontOfSize:size weight:NSFontWeightRegular];
    f.textColor = color;
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    [(NSTextFieldCell *)f.cell setUsesSingleLineMode:YES];
    return f;
}

// A small rounded "pill" showing the trigger, like Raycast/Alfred.
- (NSView *)triggerBadge:(NSString *)trigger {
    NSFont *font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
    NSSize textSize = [trigger sizeWithAttributes:@{NSFontAttributeName : font}];
    CGFloat padX = 8, padY = 3;
    CGFloat h = ceil(textSize.height) + 2 * padY;
    CGFloat w = ceil(textSize.width) + 2 * padX;

    NSView *badge = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 5;
    badge.layer.backgroundColor =
        [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.14].CGColor;

    NSTextField *t = [self plainLabel:12 color:[NSColor secondaryLabelColor]];
    t.font = font;
    t.stringValue = trigger;
    t.alignment = NSTextAlignmentCenter;
    t.frame = NSMakeRect(0, (h - textSize.height) / 2.0 - 1, w, textSize.height + 2);
    [badge addSubview:t];
    return badge;
}

// ----------------------------- interaction --------------------------------

- (void)controlTextDidChange:(NSNotification *)obj {
    [self filter:searchField.stringValue];
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(moveDown:)) { [self moveSelectionBy:1]; return YES; }
    if (commandSelector == @selector(moveUp:)) { [self moveSelectionBy:-1]; return YES; }
    if (commandSelector == @selector(insertNewline:)) { [self commitSelection]; return YES; }
    if (commandSelector == @selector(cancelOperation:)) { [self cancel]; return YES; }
    return NO;
}

- (void)moveSelectionBy:(NSInteger)delta {
    if (filtered.count == 0) return;
    NSInteger row = tableView.selectedRow + delta;
    row = MAX(0, MIN(row, (NSInteger)filtered.count - 1));
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [tableView scrollRowToVisible:row];
}

- (void)tableDoubleClicked:(id)sender { [self commitSelection]; }

- (void)commitSelection {
    NSInteger row = tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)filtered.count) {
        result = (int32_t)[filtered[row] integerValue];
    }
    [self finish];
}

- (void)cancel {
    result = -1;
    [self finish];
}

- (void)finish {
    [window orderOut:nil];
    [NSApp stopModalWithCode:(result >= 0 ? NSModalResponseOK : NSModalResponseCancel)];
    // stopModal only takes effect on the modal loop's next event; post a dummy
    // one so runModalForWindow: returns immediately rather than hanging.
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                        subtype:0
                                          data1:0
                                          data2:0];
    [NSApp postEvent:wake atStart:YES];
}

// ------------------------------- run --------------------------------------

- (int32_t)run {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect vf = screen.visibleFrame;
    NSRect wf = window.frame;
    CGFloat x = vf.origin.x + (vf.size.width - wf.size.width) / 2.0;
    CGFloat y = vf.origin.y + vf.size.height * 0.62;
    [window setFrameOrigin:NSMakePoint(x, y)];

    // Take key focus for typing WITHOUT activating espanso, so the app the user
    // was in stays frontmost and the selected expansion injects into it.
    [window orderFrontRegardless];
    [window makeKeyWindow];
    [window makeFirstResponder:searchField];

    [NSApp runModalForWindow:window];
    return result;
}

@end

int32_t espanso_show_search_panel(NSString *hint, NSArray<NSDictionary *> *items) {
    @autoreleasepool {
        EspansoSearchController *controller =
            [[EspansoSearchController alloc] initWithItems:items hint:hint];
        return [controller run];
    }
}
