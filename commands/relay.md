---
description: ctx-relay settings and manual rotation (threshold=N growth=N emergency=N autoclear=on|off [--save] | now)
argument-hint: [threshold=50] [growth=15] [emergency=90] [autoclear=on|off] [--save] | now
allowed-tools: Bash(@CTX_RELAY_BIN@:*)
---
!`a='$ARGUMENTS'; if [ "$a" = now ]; then @CTX_RELAY_BIN@ now; else @CTX_RELAY_BIN@ config $a; fi`

Reply with the output above verbatim and nothing else. Do not run any other tools.
