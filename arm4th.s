.include "common.s"

###############################################################################
# FORTH PRIMITIVES                                                            #
###############################################################################

defcode "enter",enter
  push  ip, rp
  mov   ip, lr
  next

defcode "exit",exit
  pop   ip, rp
  next

defcode "halt",halt
  b     .

defword "init",init
  _xt exit

