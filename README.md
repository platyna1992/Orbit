# Orbit

A native macOS system monitor with a translucent AppKit surface and compact cards for CPU, unified memory, and home-volume storage. Orbit's mark uses three thin open orbital arcs around a centered dot.

## Build

Requires Xcode 27 or later. Accept the Xcode license once, then run `make app` to build `build/Orbit.app` and `build/Orbit.zip`.

## Current readings

- CPU utilization is measured from Mach processor ticks and refreshed every 1.5 seconds.
- Memory usage and available memory are estimated from the system VM page counts.
- Storage usage and available capacity come from the user's home volume.
- The thermal card uses macOS's system-wide thermal state (`nominal`, `fair`, `serious`, or `critical`); it is not a CPU or GPU temperature reading.
- The **Widget** button opens a compact floating summary panel inside the same Orbit process. It can be dragged around the desktop and closed/reopened from the main window.
- Orbit includes a native WidgetKit extension with small and medium desktop/Notification Center layouts. The extension samples system metrics independently and requests a refresh every ten minutes; WidgetKit controls the actual refresh cadence.
- Launch Services is configured to prohibit multiple Orbit instances; closing the main window hides it so launching Orbit again can restore the existing window.
