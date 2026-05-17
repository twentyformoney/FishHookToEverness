#FishhooktoEverness

Self-owned-target sandbox for learning macOS dylib injection, function hooking (fishhook), Obj-C method swizzling, and in-process ImGui overlays. 
## Components

- `nte/` — a tiny Metal-rendered "NTE" with a globally-exported `g_player` struct.
- `payload/` — a dylib that, when loaded  via `DYLD_INSERT_LIBRARIES`, draws an ImGui overlay inside  render loop, swizzles its Metal commit, and mutates `g_player` from a worker thread.

## Build

```bash
cmake -B build -G Ninja
cmake --build build
```

## Run (with injection)
soon ASAP

