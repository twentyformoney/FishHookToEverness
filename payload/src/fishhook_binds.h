#pragma once

// Rebinds the C-function symbols we intercept (MTLCreateSystemDefaultDevice,
// MTLCopyAllDevices, fopen) via fishhook. Call once at startup.
void njyn_install_fishhook_binds(void);
