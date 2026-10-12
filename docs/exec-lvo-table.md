# Table LVO exec.library — V34 (Kickstart 1.3)

> **Référence d'ABI (piste CLEAN).** Offsets et ordre issus du **NDK 3.2 `FD/exec_lib.fd`**
> (consulté, non redistribué) : `##bias 30`, donc 1re fonction `Supervisor` = -30 ;
> offset(i) = -(30+6·i). Les vecteurs standard `Open`-6/`Close`-12/`Expunge`-18/réservé-24
> précèdent (non listés par le fd). Recoupé avec AROS `exec.conf` et nos ancres d'analyse.

**Frontière V34 (dernière fonction < V36) : `CopyMemQuick` (-630).** `lib_NegSize` V34 = **630 (0x276)**, soit **105 vecteurs** de 6 o.

Ceci tranche le conflit noté en M2.1 : `AddMemList`/`CopyMem`/`CopyMemQuick` sont bien V34
(V33+, cf. le fd) ; `CacheClearU` (-636) est la 1re V36. Notre analyse ROM (~102) sous-estimait.

| offset | fonction | vis. | M2.1 |
|-------:|----------|:----:|:----:|
|     -6 | Open | pub | ✅ |
|    -12 | Close | pub | ✅ |
|    -18 | Expunge | pub | ✅ |
|    -24 | *(réservé)* | pub | — |
|    -30 | Supervisor | pub |  |
|    -36 | execPrivate1 | priv |  |
|    -42 | execPrivate2 | priv |  |
|    -48 | execPrivate3 | priv |  |
|    -54 | execPrivate4 | priv |  |
|    -60 | execPrivate5 | priv |  |
|    -66 | execPrivate6 | priv |  |
|    -72 | InitCode | pub |  |
|    -78 | InitStruct | pub |  |
|    -84 | MakeLibrary | pub |  |
|    -90 | MakeFunctions | pub |  |
|    -96 | FindResident | pub |  |
|   -102 | InitResident | pub |  |
|   -108 | Alert | pub |  |
|   -114 | Debug | pub |  |
|   -120 | Disable | pub | ✅ |
|   -126 | Enable | pub | ✅ |
|   -132 | Forbid | pub | ✅ |
|   -138 | Permit | pub | ✅ |
|   -144 | SetSR | pub |  |
|   -150 | SuperState | pub |  |
|   -156 | UserState | pub |  |
|   -162 | SetIntVector | pub |  |
|   -168 | AddIntServer | pub |  |
|   -174 | RemIntServer | pub |  |
|   -180 | Cause | pub |  |
|   -186 | Allocate | pub |  |
|   -192 | Deallocate | pub |  |
|   -198 | AllocMem | pub | ✅ |
|   -204 | AllocAbs | pub |  |
|   -210 | FreeMem | pub | ✅ |
|   -216 | AvailMem | pub |  |
|   -222 | AllocEntry | pub |  |
|   -228 | FreeEntry | pub |  |
|   -234 | Insert | pub |  |
|   -240 | AddHead | pub | ✅ |
|   -246 | AddTail | pub | ✅ |
|   -252 | Remove | pub | ✅ |
|   -258 | RemHead | pub |  |
|   -264 | RemTail | pub |  |
|   -270 | Enqueue | pub |  |
|   -276 | FindName | pub | ✅ |
|   -282 | AddTask | pub |  |
|   -288 | RemTask | pub |  |
|   -294 | FindTask | pub |  |
|   -300 | SetTaskPri | pub |  |
|   -306 | SetSignal | pub |  |
|   -312 | SetExcept | pub |  |
|   -318 | Wait | pub |  |
|   -324 | Signal | pub |  |
|   -330 | AllocSignal | pub |  |
|   -336 | FreeSignal | pub |  |
|   -342 | AllocTrap | pub |  |
|   -348 | FreeTrap | pub |  |
|   -354 | AddPort | pub |  |
|   -360 | RemPort | pub |  |
|   -366 | PutMsg | pub |  |
|   -372 | GetMsg | pub |  |
|   -378 | ReplyMsg | pub |  |
|   -384 | WaitPort | pub |  |
|   -390 | FindPort | pub |  |
|   -396 | AddLibrary | pub |  |
|   -402 | RemLibrary | pub |  |
|   -408 | OldOpenLibrary | pub |  |
|   -414 | CloseLibrary | pub |  |
|   -420 | SetFunction | pub |  |
|   -426 | SumLibrary | pub |  |
|   -432 | AddDevice | pub |  |
|   -438 | RemDevice | pub |  |
|   -444 | OpenDevice | pub |  |
|   -450 | CloseDevice | pub |  |
|   -456 | DoIO | pub |  |
|   -462 | SendIO | pub |  |
|   -468 | CheckIO | pub |  |
|   -474 | WaitIO | pub |  |
|   -480 | AbortIO | pub |  |
|   -486 | AddResource | pub |  |
|   -492 | RemResource | pub |  |
|   -498 | OpenResource | pub |  |
|   -504 | execPrivate7 | priv |  |
|   -510 | execPrivate8 | priv |  |
|   -516 | execPrivate9 | priv |  |
|   -522 | RawDoFmt | pub |  |
|   -528 | GetCC | pub |  |
|   -534 | TypeOfMem | pub |  |
|   -540 | Procure | pub |  |
|   -546 | Vacate | pub |  |
|   -552 | OpenLibrary | pub |  |
|   -558 | InitSemaphore | pub |  |
|   -564 | ObtainSemaphore | pub |  |
|   -570 | ReleaseSemaphore | pub |  |
|   -576 | AttemptSemaphore | pub |  |
|   -582 | ObtainSemaphoreList | pub |  |
|   -588 | ReleaseSemaphoreList | pub |  |
|   -594 | FindSemaphore | pub |  |
|   -600 | AddSemaphore | pub |  |
|   -606 | RemSemaphore | pub |  |
|   -612 | SumKickData | pub |  |
|   -618 | AddMemList | pub |  |
|   -624 | CopyMem | pub |  |
|   -630 | CopyMemQuick | pub |  |

## Post-V34 (NE PAS exposer en 1.3)
CacheClearU (-636), CacheClearE (-642), CacheControl (-648), CreateIORequest (-654), DeleteIORequest (-660), CreateMsgPort (-666), DeleteMsgPort (-672), ObtainSemaphoreShared (-678), AllocVec (-684), FreeVec (-690), CreatePool (-696), DeletePool (-702), AllocPooled (-708), FreePooled (-714), AttemptSemaphoreShared (-720), ColdReboot (-726), StackSwap (-732), execPrivate10 (-738), execPrivate11 (-744), execPrivate12 (-750), execPrivate13 (-756), CachePreDMA (-762), CachePostDMA (-768), AddMemHandler (-774), RemMemHandler (-780), ObtainQuickVector (-786), execPrivate14 (-792), execPrivate15 (-798), execPrivate16 (-804), execPrivate17 (-810), execPrivate18 (-816), execPrivate19 (-822), NewMinList (-828), execPrivate20 (-834), execPrivate21 (-840), execPrivate22 (-846), execPrivate23 (-852), execPrivate24 (-858), execPrivate25 (-864), execPrivate26 (-870), execPrivate27 (-876), execPrivate28 (-882), execPrivate29 (-888), execPrivate30 (-894), execPrivate31 (-900), execPrivate32 (-906), execPrivate33 (-912)
