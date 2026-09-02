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

#ifndef ESPANSO_UI_SEARCH_PANEL_H
#define ESPANSO_UI_SEARCH_PANEL_H

#import <Cocoa/Cocoa.h>
#include <stdint.h>

// Runs a modal Spotlight-style search panel on the current (main) thread.
// `items` is an array of dictionaries: { "label": NSString, "trigger": NSString
// (optional), "terms": NSArray<NSString> (optional) }.
// Returns the ORIGINAL index of the chosen item, or -1 if the user cancelled.
int32_t espanso_show_search_panel(NSString *hint, NSArray<NSDictionary *> *items);

#endif // ESPANSO_UI_SEARCH_PANEL_H
