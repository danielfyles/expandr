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

static const CGFloat kPanelWidth = 640.0;
static const CGFloat kFieldHeight = 46.0;
static const CGFloat kRowHeight = 42.0;
static const NSInteger kMaxVisibleRows = 8;

// ---------------------------------------------------------------------------
// A borderless panel that is allowed to become key/main so its text field can
// receive keystrokes even though espanso is a menu-bar (accessory) app.
// ---------------------------------------------------------------------------
@interface EspansoSearchWindow : NSPanel
@end

@implementation EspansoSearchWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// ---------------------------------------------------------------------------
// Controller: owns the field + table, does the filtering and key handling, and
// drives a modal session that returns the chosen original index.
// ---------------------------------------------------------------------------
@interface EspansoSearchController
    : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate> {
@public
    NSArray<NSDictionary *> *allItems;    // original items
    NSMutableArray<NSNumber *> *filtered; // original indices matching the query
    NSPanel *window;
    NSTextField *searchField;
    NSTableView *tableView;
    NSScrollView *scrollView;
    int32_t result;                       // chosen original index, or -1
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
    // A non-activating panel can take key focus for text input WITHOUT
    // activating espanso, so the app the user was typing into stays frontmost
    // (keeps injection working) and espanso never shows a Dock / Cmd-Tab icon.
    window = [[EspansoSearchWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.level = NSFloatingWindowLevel;
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.hasShadow = YES;
    window.delegate = self;
    window.releasedWhenClosed = NO;

    // Rounded, blurred background that adapts to light/dark automatically.
    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:frame];
    bg.material = NSVisualEffectMaterialHUDWindow;
    bg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bg.state = NSVisualEffectStateActive;
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = 12.0;
    bg.layer.masksToBounds = YES;
    window.contentView = bg;

    // Search field
    searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 0, kPanelWidth - 32, kFieldHeight)];
    searchField.font = [NSFont systemFontOfSize:22 weight:NSFontWeightRegular];
    searchField.bezeled = NO;
    searchField.bordered = NO;
    searchField.drawsBackground = NO;
    searchField.focusRingType = NSFocusRingTypeNone;
    searchField.delegate = self;
    searchField.placeholderString = (hint.length > 0) ? hint : @"Search your snippets…";
    [(NSTextFieldCell *)searchField.cell setWraps:NO];
    [(NSTextFieldCell *)searchField.cell setScrollable:YES];
    [bg addSubview:searchField];
    window.initialFirstResponder = searchField;

    // Results table inside a scroll view
    scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 0)];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.automaticallyAdjustsContentInsets = NO;

    tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    tableView.headerView = nil;
    tableView.backgroundColor = [NSColor clearColor];
    tableView.rowHeight = kRowHeight;
    tableView.intercellSpacing = NSMakeSize(0, 0);
    tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.action = @selector(tableClicked:);
    tableView.target = self;
    tableView.doubleAction = @selector(tableDoubleClicked:);
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.width = kPanelWidth;
    [tableView addTableColumn:col];
    scrollView.documentView = tableView;
    [bg addSubview:scrollView];
}

// ------------------------------ filtering ---------------------------------

// Safely read an NSString value from a JSON dictionary (JSON null decodes to
// NSNull, which crashes on NSString messaging).
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
    // subsequence (fuzzy) match: every query char appears in order
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
    CGFloat listHeight = rows * kRowHeight;
    CGFloat total = kFieldHeight + (rows > 0 ? listHeight + 1 : 0);

    NSRect wf = window.frame;
    CGFloat dy = total - wf.size.height;   // grow from the top downwards
    wf.origin.y -= dy;
    wf.size.height = total;
    [window setFrame:wf display:YES];

    NSView *bg = window.contentView;
    searchField.frame = NSMakeRect(16, total - kFieldHeight, kPanelWidth - 32, kFieldHeight);
    scrollView.frame = NSMakeRect(0, 0, kPanelWidth, total - kFieldHeight);
    (void)bg;
}

// --------------------------- table data/view ------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return filtered.count; }

- (NSView *)tableView:(NSTableView *)tv
    viewForTableColumn:(NSTableColumn *)col
                   row:(NSInteger)row {
    NSDictionary *item = allItems[[filtered[row] unsignedIntegerValue]];

    NSView *cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, kRowHeight)];

    NSTextField *label = [self makeLabelWithSize:15 color:[NSColor labelColor] bold:NO];
    label.stringValue = stringValue(item[@"label"]) ?: @"";
    label.frame = NSMakeRect(18, 0, kPanelWidth - 220, kRowHeight);
    [cell addSubview:label];

    NSString *trigger = stringValue(item[@"trigger"]);
    if (trigger.length > 0) {
        NSTextField *tag = [self makeLabelWithSize:13 color:[NSColor secondaryLabelColor] bold:NO];
        tag.stringValue = trigger;
        tag.alignment = NSTextAlignmentRight;
        tag.frame = NSMakeRect(kPanelWidth - 196, 0, 178, kRowHeight);
        [cell addSubview:tag];
    }
    return cell;
}

- (NSTextField *)makeLabelWithSize:(CGFloat)size color:(NSColor *)color bold:(BOOL)bold {
    NSTextField *f = [[NSTextField alloc] init];
    f.bezeled = NO;
    f.bordered = NO;
    f.editable = NO;
    f.selectable = NO;
    f.drawsBackground = NO;
    f.font = [NSFont systemFontOfSize:size weight:(bold ? NSFontWeightSemibold : NSFontWeightRegular)];
    f.textColor = color;
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    [(NSTextFieldCell *)f.cell setUsesSingleLineMode:YES];
    return f;
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row { return kRowHeight; }

// ----------------------------- interaction --------------------------------

- (void)controlTextDidChange:(NSNotification *)obj {
    [self filter:searchField.stringValue];
}

// Arrow/Enter/Esc handling while typing in the field.
- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(moveDown:)) {
        [self moveSelectionBy:1];
        return YES;
    }
    if (commandSelector == @selector(moveUp:)) {
        [self moveSelectionBy:-1];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:)) {
        [self commitSelection];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self cancel];
        return YES;
    }
    return NO;
}

- (void)moveSelectionBy:(NSInteger)delta {
    if (filtered.count == 0) return;
    NSInteger row = tableView.selectedRow + delta;
    row = MAX(0, MIN(row, (NSInteger)filtered.count - 1));
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [tableView scrollRowToVisible:row];
}

- (void)tableClicked:(id)sender { /* selection follows click automatically */ }
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
    // stopModal only takes effect when the modal loop next processes an event;
    // post a dummy one so runModalForWindow: returns immediately instead of
    // hanging until some stray event arrives (which caused a long delay before
    // the expansion was injected).
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
    // Position: horizontally centred, upper third of the active screen.
    NSScreen *screen = [NSScreen mainScreen];
    NSRect vf = screen.visibleFrame;
    NSRect wf = window.frame;
    CGFloat x = vf.origin.x + (vf.size.width - wf.size.width) / 2.0;
    CGFloat y = vf.origin.y + vf.size.height * 0.62;
    [window setFrameOrigin:NSMakePoint(x, y)];

    // Take key focus for typing WITHOUT activating espanso (non-activating
    // panel), so the app the user was in stays frontmost and active — the
    // selected expansion then injects straight into it.
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
