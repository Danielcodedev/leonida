# P-1: asynchronous present on an 8 GB card

`LEONIDA_ASYNC_PRESENT=1` moves presentation off the thread that submits, so the copy-back thread no longer waits on
a present it has nothing to do with. Off by default; it is a setting in `[graphics]` and in the environment.

Two pairs of runs, same room, Series X, after the shader warm-up, 512 MB texture staging, six readings a run, one
minute after the world appeared, diagnostics build:

| Pair | Usual frame without | Usual frame with |
|---|---|---|
| 1 | 175 ms | 127 ms |
| 2 | 183 ms | 139 ms |

In the single runs before the pairs, the copy-back thread's wait with nothing to land fell from 82.5 ms a frame to
54.5 ms. Of four switches tried on the copy path it is the only one whose frame, card-idle and copy-back figures all
moved the same way. `LEONIDA_RELAY=0` reproduced the earlier result (645 ms against 489 ms), so the relay stays on;
`LEONIDA_COPY_CHANGED=1` (130 ms), `LEONIDA_TEXTURE_CATCHUP=1` (133 ms) and `LEONIDA_HEAP_SYNC_TABLES=1` (151 ms)
gave nothing or worse.

Measured on an RTX 3060 Ti 8 GB with a Ryzen 5 5600 and 16 GB of RAM, driver 621.40, Windows 11 26H2, build at
`b6cea00`. Other 8 GB cards were not measured.

The combined profile for this card is proposed in pull request #92 as `nvidia-8gb`, which sets this switch together
with the 512 MB texture staging; this note records the switch and its figures, and adds no profile of its own so an
8 GB owner has one name to enable, not three.
