# ARMv7 Forth kernel/interpreter

A basic forth interpreter for ARMv7 machines

# Requirements
You will need the `arm-none-eabi-gcc` package as well as `qemu` installed on your system.

# Build
`cd arm4th`
`make`

The arm-none-eabi-gcc package must be in your `PATH`.
The `make` command will produce armforth.bin.

# Usage
To run the armforth binary on qemu:
`./emulator -nogdb`

You won't see much now since the forth kernel will halt on boot...
