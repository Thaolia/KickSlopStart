# Table LVO exec.library — V34 (Kickstart 1.3)

> **Piste CLEAN / référence d'ABI.** Offsets dérivés de l'ordre de la functionlist
> d'AROS (`rom/exec/exec.conf`, référence lecture seule) + marqueurs `.version`, **recoupés**
> contre nos ancres confirmés (analyse ROM + tutoriels publics). Mapping : `Open`=-6,
> `Close`=-12, puis bias 30 depuis `Supervisor`=-30 (offset = -(30+6·(idx-2)) pour idx≥2).
> `Expunge` (-18) et le vecteur réservé (-24) ne sont pas dans la functionlist AROS.

**V34 : jusqu'à `CopyMemQuick` (-630). `lib_NegSize` V34 = 630 (0x276), soit 105 vecteurs de 6 octets.**

**Conflit de queue à trancher** : notre analyse ROM situait la frontière V34 à ~102 LVO
(`AddMemList`/`CopyMem`/`CopyMemQuick` exclus) ; les marqueurs `.version` d'AROS les donnent V33
(donc présents en V34, d'où 105). À confirmer contre le **vrai `exec_lib.fd` V34 (NDK)** avant de
figer `lib_NegSize` en M2.2. Sans impact sur M2.1 : les fonctions implémentées (jusqu'à
`FindName` -276) ont des offsets **certains** (recoupés par 3 sources).

| LVO | offset | ver | fonction | M2.1 |
|----:|-------:|----:|----------|:----:|
|   1 |    -6 |  33 | Open | ✅ |
|   2 |   -12 |  33 | Close | ✅ |
|   3 |   -18 |  33 | Expunge | ✅ |
|   4 |   -24 |  33 | *(réservé)* | — |
|   5 |   -30 |  33 | Supervisor |  |
|   6 |   -36 |  33 | ExitIntr |  |
|   7 |   -42 |  33 | Schedule |  |
|   8 |   -48 |  33 | Reschedule |  |
|   9 |   -54 |  33 | Switch |  |
|  10 |   -60 |  33 | Dispatch |  |
|  11 |   -66 |  33 | Exception |  |
|  12 |   -72 |  33 | InitCode |  |
|  13 |   -78 |  33 | InitStruct |  |
|  14 |   -84 |  33 | MakeLibrary |  |
|  15 |   -90 |  33 | MakeFunctions |  |
|  16 |   -96 |  33 | FindResident |  |
|  17 |  -102 |  33 | InitResident |  |
|  18 |  -108 |  33 | Alert |  |
|  19 |  -114 |  33 | Debug |  |
|  20 |  -120 |  33 | Disable | ✅ |
|  21 |  -126 |  33 | Enable | ✅ |
|  22 |  -132 |  33 | Forbid | ✅ |
|  23 |  -138 |  33 | Permit | ✅ |
|  24 |  -144 |  33 | SetSR |  |
|  25 |  -150 |  33 | SuperState |  |
|  26 |  -156 |  33 | UserState |  |
|  27 |  -162 |  33 | SetIntVector |  |
|  28 |  -168 |  33 | AddIntServer |  |
|  29 |  -174 |  33 | RemIntServer |  |
|  30 |  -180 |  33 | Cause |  |
|  31 |  -186 |  33 | Allocate |  |
|  32 |  -192 |  33 | Deallocate |  |
|  33 |  -198 |  33 | AllocMem | ✅ |
|  34 |  -204 |  33 | AllocAbs |  |
|  35 |  -210 |  33 | FreeMem | ✅ |
|  36 |  -216 |  33 | AvailMem |  |
|  37 |  -222 |  33 | AllocEntry |  |
|  38 |  -228 |  33 | FreeEntry |  |
|  39 |  -234 |  33 | Insert |  |
|  40 |  -240 |  33 | AddHead | ✅ |
|  41 |  -246 |  33 | AddTail | ✅ |
|  42 |  -252 |  33 | Remove | ✅ |
|  43 |  -258 |  33 | RemHead |  |
|  44 |  -264 |  33 | RemTail |  |
|  45 |  -270 |  33 | Enqueue |  |
|  46 |  -276 |  33 | FindName | ✅ |
|  47 |  -282 |  33 | AddTask |  |
|  48 |  -288 |  33 | RemTask |  |
|  49 |  -294 |  33 | FindTask |  |
|  50 |  -300 |  33 | SetTaskPri |  |
|  51 |  -306 |  33 | SetSignal |  |
|  52 |  -312 |  33 | SetExcept |  |
|  53 |  -318 |  33 | Wait |  |
|  54 |  -324 |  33 | Signal |  |
|  55 |  -330 |  33 | AllocSignal |  |
|  56 |  -336 |  33 | FreeSignal |  |
|  57 |  -342 |  33 | AllocTrap |  |
|  58 |  -348 |  33 | FreeTrap |  |
|  59 |  -354 |  33 | AddPort |  |
|  60 |  -360 |  33 | RemPort |  |
|  61 |  -366 |  33 | PutMsg |  |
|  62 |  -372 |  33 | GetMsg |  |
|  63 |  -378 |  33 | ReplyMsg |  |
|  64 |  -384 |  33 | WaitPort |  |
|  65 |  -390 |  33 | FindPort |  |
|  66 |  -396 |  33 | AddLibrary |  |
|  67 |  -402 |  33 | RemLibrary |  |
|  68 |  -408 |  33 | OldOpenLibrary |  |
|  69 |  -414 |  33 | CloseLibrary |  |
|  70 |  -420 |  33 | SetFunction |  |
|  71 |  -426 |  33 | SumLibrary |  |
|  72 |  -432 |  33 | AddDevice |  |
|  73 |  -438 |  33 | RemDevice |  |
|  74 |  -444 |  33 | OpenDevice |  |
|  75 |  -450 |  33 | CloseDevice |  |
|  76 |  -456 |  33 | DoIO |  |
|  77 |  -462 |  33 | SendIO |  |
|  78 |  -468 |  33 | CheckIO |  |
|  79 |  -474 |  33 | WaitIO |  |
|  80 |  -480 |  33 | AbortIO |  |
|  81 |  -486 |  33 | AddResource |  |
|  82 |  -492 |  33 | RemResource |  |
|  83 |  -498 |  33 | OpenResource |  |
|  84 |  -504 |  33 | RawIOInit |  |
|  85 |  -510 |  33 | RawMayGetChar |  |
|  86 |  -516 |  33 | RawPutChar |  |
|  87 |  -522 |  33 | RawDoFmt |  |
|  88 |  -528 |  33 | GetCC |  |
|  89 |  -534 |  33 | TypeOfMem |  |
|  90 |  -540 |  33 | Procure |  |
|  91 |  -546 |  33 | Vacate |  |
|  92 |  -552 |  33 | OpenLibrary |  |
|  93 |  -558 |  33 | InitSemaphore |  |
|  94 |  -564 |  33 | ObtainSemaphore |  |
|  95 |  -570 |  33 | ReleaseSemaphore |  |
|  96 |  -576 |  33 | AttemptSemaphore |  |
|  97 |  -582 |  33 | ObtainSemaphoreList |  |
|  98 |  -588 |  33 | ReleaseSemaphoreList |  |
|  99 |  -594 |  33 | FindSemaphore |  |
| 100 |  -600 |  33 | AddSemaphore |  |
| 101 |  -606 |  33 | RemSemaphore |  |
| 102 |  -612 |  33 | SumKickData |  |
| 103 |  -618 |  33 | AddMemList |  |
| 104 |  -624 |  33 | CopyMem |  |
| 105 |  -630 |  33 | CopyMemQuick |  |

## Fonctions POST-V34 (NE PAS exposer pour une cible 1.3)

CacheClearU (-636, V36), CacheClearE (-642, V36), CacheControl (-648, V36), CreateIORequest (-654, V36), DeleteIORequest (-660, V36), CreateMsgPort (-666, V36), DeleteMsgPort (-672, V36), ObtainSemaphoreShared (-678, V36), AllocVec (-684, V36), FreeVec (-690, V36), CreatePool (-696, V36), DeletePool (-702, V36), AllocPooled (-708, V36), FreePooled (-714, V36), AttemptSemaphoreShared (-720, V36), ColdReboot (-726, V36), StackSwap (-732, V36), ChildFree (-738, V36), ChildOrphan (-744, V36), ChildStatus (-750, V36), ChildWait (-756, V36), CachePreDMA (-762, V36), CachePostDMA (-768, V36), AddMemHandler (-774, V39), RemMemHandler (-780, V39), ObtainQuickVector (-786, V39), NewStackSwap (-792, V39), TaggedOpenLibrary (-798, V39), ReadGayle (-804, V39), VNewRawDoFmt (-810, V50), NewMinList (-816, V45), AVL_AddNode (-822, V45), AVL_RemNodeByAddress (-828, V45), AVL_RemNodeByKey (-834, V45), AVL_FindNode (-840, V45), AVL_FindPrevNodeByAddress (-846, V45), AVL_FindPrevNodeByKey (-852, V45), AVL_FindNextNodeByAddress (-858, V45), AVL_FindNextNodeByKey (-864, V45), AVL_FindFirstNode (-870, V45), AVL_FindLastNode (-876, V45), NewCreateTaskA (-882, V50), FindTaskByPID (-888, V50), AddResetCallback (-894, V50), RemResetCallback (-900, V50), AllocVecPooled (-906, V50), FreeVecPooled (-912, V50), ShutdownA (-918, V50), NewAllocEntry (-924, V50), NewAddTask (-930, V50)
