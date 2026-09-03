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
#import <CoreText/CoreText.h>

// Variable-font axis tags.
static const int kAxisWeight = 0x77676874;  // 'wght'
static const int kAxisOptical = 0x6F70737A; // 'opsz'

// Resolve a bundled variable font (registered at startup) at a given size and
// weight, falling back to a system font if unavailable.
static NSFont *espansoVariableFont(NSString *family, CGFloat size, NSDictionary *axes,
                                   NSFont *fallback) {
    NSFontDescriptor *desc = [NSFontDescriptor fontDescriptorWithFontAttributes:@{
        NSFontFamilyAttribute : family,
        (NSString *)kCTFontVariationAttribute : axes,
    }];
    NSFont *font = [NSFont fontWithDescriptor:desc size:size];
    return font ?: fallback;
}

// Body text: Newsreader (serif), medium weight.
static NSFont *espansoBodyFont(CGFloat size) {
    return espansoVariableFont(@"Newsreader", size, @{@(kAxisWeight) : @(500)},
                               [NSFont systemFontOfSize:size]);
}

// Headings: Fraunces (display serif), semibold at a display optical size.
// (Ready for the windows we build next; no heading in the search panel yet.)
__attribute__((unused)) static NSFont *espansoHeadingFont(CGFloat size) {
    return espansoVariableFont(
        @"Fraunces", size, @{@(kAxisWeight) : @(600), @(kAxisOptical) : @(72)},
        [NSFont boldSystemFontOfSize:size]);
}

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
@property (nonatomic, copy) void (^onCancel)(void);
@end

@implementation EspansoSearchWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
// Esc anywhere in the panel (e.g. when the results table has focus after a
// click) bubbles here if unhandled, so dismiss from here too.
- (void)cancelOperation:(id)sender {
    if (self.onCancel) self.onCancel();
}
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
    NSTextField *placeholderLabel;
    NSBox *separator;
    NSTableView *tableView;
    NSScrollView *scrollView;
    int32_t result;
    void (^completion)(int32_t);
    id selfRetain;  // keeps the controller alive while shown non-modally
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

// A resizable rounded-rect mask used to round the visual-effect (blur) view.
+ (NSImage *)roundedMaskWithRadius:(CGFloat)radius {
    CGFloat d = radius * 2 + 1;
    NSImage *img = [NSImage imageWithSize:NSMakeSize(d, d)
                                  flipped:NO
                           drawingHandler:^BOOL(NSRect rect) {
                             [[NSColor blackColor] set];
                             [[NSBezierPath bezierPathWithRoundedRect:rect
                                                             xRadius:radius
                                                             yRadius:radius] fill];
                             return YES;
                           }];
    img.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    img.resizingMode = NSImageResizingModeStretch;
    return img;
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
    __weak EspansoSearchController *weakSelf = self;
    ((EspansoSearchWindow *)window).onCancel = ^{ [weakSelf cancel]; };

    // Translucent, blurred background that adapts to light/dark automatically.
    // A rounded mask image rounds the *blur* itself (cornerRadius alone leaves a
    // square blur backing behind the rounded content).
    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:frame];
    bg.material = NSVisualEffectMaterialMenu;
    bg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bg.state = NSVisualEffectStateActive;
    bg.maskImage = [EspansoSearchController roundedMaskWithRadius:kCornerRadius];
    window.contentView = bg;
    contentView = bg;

    // Leading search glyph + field, laid out with Auto Layout so the field uses
    // its natural (intrinsic) height and is vertically centred — the same
    // mechanism the result rows use, which centres cleanly and never clips.
    searchIcon = [[NSImageView alloc] init];
    if (@available(macOS 11.0, *)) {
        searchIcon.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass"
                                    accessibilityDescription:nil];
    }
    searchIcon.contentTintColor = [NSColor secondaryLabelColor];
    searchIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    searchIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:searchIcon];

    // Placeholder drawn as a separate, non-editable label (added first, so it
    // sits behind the transparent field). NSTextField's built-in placeholder
    // top-aligns and clips; a plain centred label doesn't (same as the rows).
    placeholderLabel = [self plainLabel:20 color:[NSColor placeholderTextColor]];
    placeholderLabel.font = espansoBodyFont(20);
    placeholderLabel.stringValue =
        (hint.length > 0 && hint.length <= 42) ? hint : @"Search snippets…";
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:placeholderLabel];

    searchField = [[NSTextField alloc] init];
    searchField.font = espansoBodyFont(20);
    searchField.bezeled = NO;
    searchField.bordered = NO;
    searchField.drawsBackground = NO;
    searchField.focusRingType = NSFocusRingTypeNone;
    searchField.delegate = self;
    searchField.textColor = [NSColor labelColor];
    searchField.usesSingleLineMode = YES;
    [(NSTextFieldCell *)searchField.cell setWraps:NO];
    [(NSTextFieldCell *)searchField.cell setScrollable:YES];
    searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:searchField];
    window.initialFirstResponder = searchField;

    // The field band sits in the top `kFieldHeight` of the panel; centre the
    // icon, field, and placeholder on that band's centre line.
    [NSLayoutConstraint activateConstraints:@[
        [searchIcon.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:kInset],
        [searchIcon.centerYAnchor constraintEqualToAnchor:bg.topAnchor constant:kFieldHeight / 2.0],
        [searchIcon.widthAnchor constraintEqualToConstant:kSearchIconSize],
        [searchIcon.heightAnchor constraintEqualToConstant:kSearchIconSize],
        [searchField.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:12],
        [searchField.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-kInset],
        [searchField.centerYAnchor constraintEqualToAnchor:searchIcon.centerYAnchor],
        // +2 to line up with where the field editor draws its text / caret;
        // nudge down slightly for optical centring of the serif text.
        [placeholderLabel.leadingAnchor constraintEqualToAnchor:searchField.leadingAnchor constant:2],
        [placeholderLabel.centerYAnchor constraintEqualToAnchor:searchField.centerYAnchor constant:3],
    ]];

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

// Lay out the chrome for a given total window height (list grows below the
// field band; the icon + field themselves are positioned by Auto Layout).
- (void)layoutChrome:(CGFloat)total {
    CGFloat fieldTop = total - kFieldHeight;
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
    placeholderLabel.hidden = (query.length > 0);
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
    // Content inset within the row so it sits inside the inset selection pill.
    const CGFloat sideInset = 12;
    NSView *cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, kRowHeight)];

    NSTextField *label = [self plainLabel:16 color:[NSColor labelColor]];
    label.font = espansoBodyFont(16);
    label.stringValue = stringValue(item[@"label"]) ?: @"";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:label];

    [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:sideInset].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor].active = YES;

    NSString *trigger = stringValue(item[@"trigger"]);
    if (trigger.length > 0) {
        NSView *badge = [self triggerBadge:trigger];
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:badge];
        [badge.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-sideInset].active = YES;
        [badge.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor].active = YES;
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:badge.leadingAnchor constant:-10].active = YES;
    } else {
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-sideInset].active = YES;
    }
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

// A small rounded "pill" showing the trigger, like Raycast/Alfred. Sized by its
// text via Auto Layout, vertically centred on the row by the caller.
- (NSView *)triggerBadge:(NSString *)trigger {
    NSView *badge = [[NSView alloc] init];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 5;
    badge.layer.backgroundColor =
        [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.14].CGColor;

    NSTextField *t = [self plainLabel:12 color:[NSColor secondaryLabelColor]];
    t.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
    t.stringValue = trigger;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:t];

    const CGFloat padX = 8, padY = 3;
    [NSLayoutConstraint activateConstraints:@[
        [t.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:padX],
        [t.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-padX],
        [t.topAnchor constraintEqualToAnchor:badge.topAnchor constant:padY],
        [t.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-padY],
    ]];
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
    void (^c)(int32_t) = completion;
    completion = nil;
    if (c) c(result);
    selfRetain = nil;  // allow deallocation now that we're done
}

// ------------------------------- show -------------------------------------

- (void)showWithCompletion:(void (^)(int32_t))c {
    completion = [c copy];
    selfRetain = self;

    NSScreen *screen = [NSScreen mainScreen];
    NSRect vf = screen.visibleFrame;
    NSRect wf = window.frame;
    CGFloat x = vf.origin.x + (vf.size.width - wf.size.width) / 2.0;
    CGFloat y = vf.origin.y + vf.size.height * 0.62;
    [window setFrameOrigin:NSMakePoint(x, y)];

    // Take key focus for typing WITHOUT activating espanso, so the app the user
    // was in stays frontmost and the selected expansion injects into it. Shown
    // non-modally so the normal run loop drives smooth scrolling / momentum.
    [window orderFrontRegardless];
    [window makeKeyWindow];
    [window makeFirstResponder:searchField];
}

@end

void espanso_show_search_panel(NSString *hint, NSArray<NSDictionary *> *items,
                               void (^completion)(int32_t)) {
    EspansoSearchController *controller =
        [[EspansoSearchController alloc] initWithItems:items hint:hint];
    [controller showWithCompletion:completion];
}
