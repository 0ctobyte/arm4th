# ARMv7 Forth kernel

A minimal Forth kernel/interpreter for ARMv7 machines.
Currently, this kernel can run barebones on an emulated (using QEMU) Versatile Express board with Cortex-A15 machine.
It can also run on a BeagleBone Black with a Cortex-A8 CPU.

# Requirements
You will need the `arm-none-eabi-gcc` package as well as `qemu` installed on your system.

# Build
`cd arm4th`

`make`

or alternatively, to build for the BeagleBone:

`make BBB=1`

The arm-none-eabi-gcc package must be in your `PATH`.
The `make` command will produce the binary image file `arm4th.bin`

# Usage
To run the arm4th binary on qemu:
`./emulator -nogdb`
