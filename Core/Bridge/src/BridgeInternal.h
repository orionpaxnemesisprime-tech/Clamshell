// Clamshell — internal glue between Bridge.cpp and Platform.cpp.
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef CLAMSHELL_BRIDGE_INTERNAL_H
#define CLAMSHELL_BRIDGE_INTERNAL_H

#include "ClamshellBridge.h"

/// Resolves melonDS's per-instance `userdata` (a ClamshellCore*) to its callbacks and
/// their context. `*callbacks` is NULL when userdata is NULL.
void *clamshell_internal_callbacks_context(void *userdata, ClamshellCoreCallbacks **callbacks);

#endif
