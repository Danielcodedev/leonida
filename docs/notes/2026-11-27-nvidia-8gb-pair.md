# P-1: one nvidia-8gb profile for the 8 GB pair

`LEONIDA_TEXTURE_STAGE_MB=512` and `LEONIDA_ASYNC_PRESENT=1`, Series X, after the shader warm-up, usual frame from
the frame log after the world settles:

| Scene | Stock defaults | The pair |
|---|---|---|
| first gameplay room | 312 ms | **130 ms** |
| courtyard, 4,000-4,850 draws | 489 ms | **129 ms** |
| menus, setup, legal, title art | 33.3 ms | 33.3 ms (30 fps) |

Each setting alone, for reference:

| Staging a frame | Textures with no host copy | Usual frame |
|---|---|---|
| 192 (default) | 15,563 (8,646 MB) | 312 ms |
| 512 | 12,145 (8,500 MB) | 288 ms |
| 1,024 | 15,064 (10,381 MB) | 1,007 ms |

Asynchronous present took the room from 175/183 ms to 127/139 ms in two pairs of runs, with the copy-back thread's
wait falling from 82.5 to 54.5 ms. Three further switches on the copy path were tried and refused:
`LEONIDA_COPY_CHANGED=1` (130 ms, no change), `LEONIDA_TEXTURE_CATCHUP=1` (133 ms, no change) and
`LEONIDA_HEAP_SYNC_TABLES=1` (151 ms, worse); `RELAY=0` reproduced upstream's doubling (645 ms against 489 ms).

Opt-in profile `nvidia-8gb` (NVIDIA, 7,000-8,600 MB) sets the pair in one name. It replaces the two single-switch
opt-in profiles this card had (`nvidia-8gb-texture-stage`, `nvidia-8gb-async-present`), so an 8 GB owner enables one
name; their figures are the two paragraphs above. The heavier frames that remain are
relay-bound, not card-bound: in a 383 ms courtyard frame the card was 34-39 % busy, the submit thread worked 200-279 ms
while it was idle, and the hazard wait "title memory changed under shader writes" cost 23-44 ms.

Measured on an RTX 3060 Ti 8 GB, Ryzen 5 5600, 16 GB, driver 621.40, Windows 11 26H2. Not measured on other 8 GB
cards.
