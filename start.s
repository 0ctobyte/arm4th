.include "common.s"

.text
.code 32

# Minimal code for coldbooting Forth on an ARMv7 machine
.global _start
.align 2
_start:
  # Set origin = 0x10000 since this is where qemu loads the binary image
  movw  org, #0x0
  movt  org, #0x1

  # Setup the stack pointer and return stack
  ldr   r0, =name_enter
  add   r0, r0, org
  sub   r0, r0, #0x1000
  mov   rp, r0
  sub   r0, r0, #0x2000 // 8k return stack
  mov   sp, r0

  # tos magic value
  movw  r0, #0xbeef
  movt  r0, #0xdead
  mov   tos, r0

  # Finally set the ip to coldboot
  ldr   ip, =startforth
  add   ip, ip, org

  # Go to init!
  next

# Start running the Forth interpreter
startforth:
  xt init
  xt halt
