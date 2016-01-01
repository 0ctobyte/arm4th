# ARMv7 Forth interpreter

A minimal Forth interpreter for ARMv7 machines.
Currently, this interpreter can run barebones on an emulated (using QEMU) Versatile Express board with Cortex-A15 machine.

# Requirements
You will need the `arm-none-eabi-gcc` package as well as `qemu` installed on your system.

# Build
`cd arm4th`
`make`

The arm-none-eabi-gcc package must be in your `PATH`.
The `make` command will produce the binary image file `arm4th.bin`

# Usage
To run the arm4th binary on qemu:
`./emulator -nogdb`

You won't see much now since the forth kernel will halt on boot...
