# intuition-requesters-v34.md — Request / EndRequest / InitRequester / AutoRequest (intuition 34.3)

> ANALYSIS track ("dirty"). Sources: ROM `assets/kick34005.A500` (intuition 34.3) and
> `SYS:System/DiskCopy` from `wb133.adf` ("DiskCopy 1.4", `$VER: diskcopy 36.6`). (ROM routine
> addresses removed from the document: they add nothing to the implementation.)
>
> **Legend**: **[O]** observed · **[D]** deduced · **[S]** assumed. Behaviours, ABI
> layouts and constants only: **no instruction sequence is reproduced**.

---

## 0. Short answer for DiskCopy

**DiskCopy 1.4 calls neither Request, nor EndRequest, nor InitRequester.** The message "Place SOURCE
disk ( FROM disk ) in drive DF0:" and the Continue/Cancel buttons come from **AutoRequest
(−348)** [O]. In 1.3, AutoRequest is built **on top of** BuildSysRequest, which opens a **new
window** containing a **Requester** posted by Request (§5). A faithful AutoRequest therefore requires
working Request and EndRequest, **or** an AutoRequest implementation that produces the same
visible result (§5.4).

---

## 1. ABI layouts [O]

### 1.1 `struct Requester` (V34) — size **$70 = 112 bytes**

| Off. | Size | Field |
|---|---|---|
| +$00 | ptr | OlderRequest (chaining, most recent at the head) |
| +$04 | WORD | LeftEdge (relative to the window, see §2.2) |
| +$06 | WORD | TopEdge |
| +$08 | WORD | Width |
| +$0A | WORD | Height |
| +$0C | WORD | RelLeft (POINTREL) |
| +$0E | WORD | RelTop |
| +$10 | ptr | ReqGadget (gadget list) |
| +$14 | ptr | ReqBorder |
| +$18 | ptr | ReqText (IntuiText) |
| +$1C | UWORD | Flags: POINTREL $0001, **PREDRAWN $0002**, **NOISYREQ $0004**, REQOFFWINDOW $1000, **REQACTIVE $2000**, SYSREQUEST $4000, DEFERREFRESH $8000 |
| +$1E | UBYTE | BackFill (background pen) |
| +$20 | ptr | ReqLayer |
| +$24 | 32 B | ReqPad1 |
| +$44 | ptr | ImageBMap (PREDRAWN) |
| +$48 | ptr | RWindow |
| +$4C | 36 B | ReqPad2 |

### 1.2 Relevant `struct Window` fields

| Off. | Field |
|---|---|
| +$18 | Flags: **INREQUEST $4000** |
| +$24 | FirstRequest |
| +$28 | DMRequest |
| +$2C | ReqCount (WORD) |
| +$52 | IDCMPFlags: REQSET $80, REQCLEAR $1000, REQVERIFY $800 |
| +$78 | UserData: used by BuildSysRequest, see §5.2 |

---

## 2. Request(req, win) (−240) [O unless stated]

### 2.1 Effects, in order

1. `req->RWindow` := win, `req->ReqLayer` := NULL, `req->OlderRequest` := `win->FirstRequest`.
2. **Layer creation** (§2.2). If it fails ⇒ **return FALSE**, and nothing is chained.
3. **Every gadget of `ReqGadget` receives the REQGADGET bit ($1000)** in GadgetType.
4. `win->FirstRequest` := req; **`win->ReqCount` += 1**; **`win->Flags` |= INREQUEST**.
5. Drawing of the requester under LockLayerInfo (§2.3).
6. If drawing succeeded: **two deferred events** are queued for the input
   task:
   - **class 9, code 1** ⇒ IDCMP message **REQSET ($80)** to the window, if it asked for it.
     The internal table maps class 9 + code ≠ 0 to REQSET and class 9 + code 0 to
     REQCLEAR [O for the table, D for the routing];
   - a second event (internal code 11) that marks the "requester active" state for the
     active window [O; exact role S].
7. **Return value**: TRUE if the layer and the drawing succeeded, otherwise FALSE.

### 2.2 Requester layer

- **Origin**: `win->LeftEdge + req->LeftEdge`, `win->TopEdge + req->TopEdge`.
  - In a **GIMMEZEROZERO** window, BorderLeft/BorderTop are added: the requester is then
    relative to the **inner area**.
  - **POINTREL and RelLeft/RelTop are not used by Request** [O by absence]; they are
    only used for the double-menu requester (DMRequest).
- **Size**: Width/Height of the requester, **clipped** to the available space:
  - non-GZZ window: up to `Width − BorderRight` / `Height − BorderBottom`, counted from the
    left or top edge of the window;
  - GZZ window: up to GZZWidth / GZZHeight.
  - If the clipped size is ≤ 0: **no layer** (an existing layer is deleted), but
    Request still succeeds and the requester is chained, with nothing displayed.
- **Type**: **CreateBehindLayer** (layers −42), flags **LAYERSMART (2)**, no super-bitmap,
  on the screen's BitMap. `layer->Window` := win.
- **Depth**: the layer is placed **just in front of** the previous requester's layer
  (`OlderRequest->ReqLayer`) if there is one, otherwise in front of **`win->WLayer`**, via
  **MoveLayerInFrontOf** (layers −168). It is therefore in front of the window and below the other
  windows placed above it.

### 2.3 Rendering

- `req->Flags |= REQACTIVE`.
- Initialisation of the PropInfo of the requester's proportional gadgets (container borders,
  as for windows).
- No layer ⇒ nothing is drawn.
- **PREDRAWN**: **BltBitMapRastPort** (graphics −606) from `ImageBMap` to the layer's
  RastPort, at (0,0), over Width × Height, minterm $C0.
  Neither border, nor text, nor background is drawn; **only the gadgets are** [O: the PREDRAWN
  branch only does the copy; the gadgets are D, see the remark].
- **Otherwise**, in a RastPort cloned onto the layer (screen font):
  1. **RectFill of the background** (0,0)–(Width−1, Height−1) with the **BackFill** pen, in JAM1;
  2. **DrawBorder(ReqBorder, 0, 0)**;
  3. **PrintIText(ReqText, 0, 0)**;
  4. **rendering of the ReqGadget list** (common routine, in reverse: the first in the list is
     drawn last, see `intuition-gzz-v34.md` §6).

Remark: in the PREDRAWN branch, gadget rendering does not appear in the same routine.
It happens through the layer refresh [S].

### 2.4 Domain of requester gadgets [O]

For a REQGADGET gadget:
- **domain** = (req LeftEdge, req TopEdge, Width, Height), plus BorderLeft/Top if the window
  is GZZ;
- **rendering layer** = ReqLayer.

Gadget coordinates are therefore **relative to the requester's corner**, and the GRELxxx ones
relative to its width and height.

---

## 3. Input while a requester is up [O unless stated]

### 3.1 Left button (SELECTDOWN)

- The search for the gadget under the pointer is done **only in the active window**:
  - pointer over the layer of the **first** requester (`FirstRequest->ReqLayer`) ⇒ **its ReqGadget
    list** is walked, in forward order (the first one containing the point wins);
  - otherwise ⇒ the window's list is walked.
- When the window has a requester, **only REQGADGET or SYSGADGET ($8000) gadgets are
  accepted**. The window's application gadgets are **inert**.
  - The system **close** gadget is also **refused**: its click is ignored.
  - The other system gadgets (drag, depth, size) **remain usable**.
- GADGDISABLED gadgets are never selected.
- Click in **another window** or on another screen ⇒ normal processing: the active window can
  be changed.
- **Only the most recent requester** (FirstRequest) receives the clicks.

### 3.2 Other events (keys, right button, moves…)

- **NOISYREQ** requester ⇒ events pass to the window as usual.
- Otherwise ⇒ they are **swallowed**.
- **Menus**: in that case, the right button does not open the window's menus [D, from
  "swallowed"].

### 3.3 Messages from requester gadgets

- GADGETDOWN / GADGETUP are sent according to the normal rules (GADGIMMEDIATE / RELVERIFY), with
  **IAddress = the gadget** [D: common gadget path].
- **ENDGADGET** (Activation $0004), on release:
  - the `FirstRequest` requester is **removed** (§4.1);
  - a **class 9 code 0 ⇒ REQCLEAR** event is queued;
  - **ReqCount −= 1**, and if the count drops to 0, **INREQUEST is cleared**;
  - the window is then repaired.
  - The REQCLEAR is sent here for **every** requester ended by ENDGADGET [O].

---

## 4. EndRequest(req, win) (−120) and InitRequester (−138) [O]

### 4.1 Common removal (EndRequest and ENDGADGET)

1. `req->Flags &= ~REQACTIVE`.
2. Search for `req` in the `win->FirstRequest` chain. **If it is not there ⇒ nothing is
   done** (EndRequest returns with no effect).
3. Removal from the chain. A requester that is not at the head can be removed.
4. **DeleteLayer(0, ReqLayer)**, then `ReqLayer` := NULL. The layers repair the uncovered area.

### 4.2 EndRequest-specific continuation

- **ReqCount −= 1**. If it drops to **0**:
  - event **class 9 code 0 ⇒ REQCLEAR**;
  - **INREQUEST cleared**.
- In all cases, a **window repair** event is then queued.
- No meaningful return value.

### 4.3 InitRequester(req)

**Zeroes the 112 ($70) bytes** of the structure, and nothing else [O].

### 4.4 SetDMRequest (−258) / ClearDMRequest (−48)

- **SetDMRequest(win, req)**: `win->DMRequest` (+$28) := req, **unless** the current DMRequest
  is active (REQACTIVE) ⇒ refused, returns FALSE. Otherwise TRUE.
- **ClearDMRequest(win)**: same routine with NULL, therefore refused if the DMRequest is active.
- Their display by right-button double click (DMRequest, POINTREL) is not used by
  DiskCopy and has not been analysed.

---

## 5. AutoRequest (−348) / BuildSysRequest (−360) / FreeSysRequest (−372) [O unless stated]

### 5.1 AutoRequest(win, body, pos, neg, pflag, nflag, W, H)

1. **IDCMP of the created window** = `pflag | nflag | GADGETUP ($40) | RAWKEY ($400)`.
2. Call to **BuildSysRequest(win, body, pos, neg, IDCMP, W, H)**. If it returns **0 or 1**,
   i.e. the Alert fallback (§5.3), that result is **directly** the return value.
3. If the created window's screen is not the first screen ⇒ **ScreenToFront** of that screen.
4. **Loop**: GetMsg on the created window's UserPort, Wait on its signal when the port
   is empty. For each message:
   - class ∈ **nflag** ⇒ **FALSE**;
   - class ∈ **pflag** ⇒ **TRUE**;
   - **GADGETUP** ⇒ **TRUE if GadgetID ≠ 0** (positive gadget), **FALSE if GadgetID = 0**
     (negative);
   - **RAWKEY** with **left Amiga** (bit $40 of the qualifier's low-order byte):
     - code **$34** (V) ⇒ TRUE, only if `pos` exists;
     - code **$35** (B) ⇒ FALSE;
   - any other message is ignored.
   - **Messages are not replied to** (no ReplyMsg in the loop). CloseWindow
     reclaims them.
5. **FreeSysRequest(window)**, then return of the boolean.

### 5.2 BuildSysRequest(win, body, pos, neg, idcmp, W, H)

1. **NewWindow** (ROM template):
   - Left 0, Top 0, **Width = W, Height = H**;
   - DetailPen/BlockPen: those of `win` (otherwise $FF/$FF);
   - IDCMPFlags = idcmp;
   - **Flags $00021047**: NOCAREREFRESH | ACTIVATE | SIMPLE_REFRESH | DEPTH | DRAG | SIZING;
   - **Title** = `win->Title`, otherwise **`"System Request"`**;
   - **Screen** = `win->WScreen`, and **Type** = `Screen->Flags & $0F` (otherwise WBENCHSCREEN);
   - **MinWidth 88, MinHeight 24, MaxWidth = W, MaxHeight = H**.
   OpenWindow. On failure ⇒ Alert fallback (§5.3).
2. **Requester** of 112 bytes allocated by AllocRemember (MEMF_PUBLIC|CLEAR), then
   **InitRequester**:
   - LeftEdge = `newwin->LeftEdge + BorderLeft`, TopEdge = `newwin->TopEdge + BorderTop`.
     Since the window is at (0,0), this amounts to the borders;
   - Width = W − BorderLeft − BorderRight, Height = H − BorderTop − BorderBottom;
   - **BackFill = 1**, **Flags |= NOISYREQ**;
   - **ReqBorder** = frame built at the requester's size;
   - **ReqText** = body.
3. **Gadgets**, allocated in the Remember list (44 bytes each), where applicable:
   - **positive** (if `pos`): **GadgetID = 1**, LeftEdge = **14**;
   - **negative**: **GadgetID = 0**, plus the **GRELRIGHT** flag;
   - common attributes [O]:
     - Flags **GRELBOTTOM ($0008)**;
     - Activation **$0101**;
     - GadgetType **REQGADGET | BOOLGADGET ($1001)**;
     - **GadgetText = pos/neg**;
     - Width = text length in pixels + 12;
     - Height = font height + 6;
     - TopEdge = −(Height + 4);
     - LeftEdge of the negative one = −(Width + 13);
     - a border at their size.
   - There is **no ENDGADGET**: the end comes from GADGETUP, handled by AutoRequest.
4. **Request(req, newwin)**. On failure: CloseWindow, then Alert fallback.
5. The Remember list is stored in **`newwin->UserData` (+$78)**. Return: the window.

### 5.2.1 Graphical detail of BuildSysRequest [O unless stated]

**Border factory** `Frame(W, H, inset r, pen p)`, used for all the borders
below:
- **a single** `struct Border` (16 bytes, MEMF_PUBLIC|CLEAR, in the Remember list):
  - LeftEdge = 0, TopEdge = 0;
  - **FrontPen = p**, **BackPen = 0**;
  - **DrawMode = JAM1 (0)**;
  - **Count = 9**;
  - NextBorder = NULL;
  - XY = 36-byte array (same allocation).
- With W' = W − 1, H' = H − 1 and s = r + 1, the **9 points** are:

  `(r, r) (W'−r, r) (W'−r, H'−r) (r, H'−r) (r, r) (s, r) (s, H'−r) (W'−s, H'−r) (W'−s, r)`

  This is a rectangle inset by `r`, followed by a second vertical stroke shifted one pixel
  inwards, on each side: the uprights are **2 pixels wide**, suited to hires.

**1. ReqBorder**:
- **a single Border** = `Frame(Width, Height of the requester, r = 1, p = 0)`, i.e. a
  **colour 0** (blue) frame inset by 1 pixel;
- the background is **BackFill = 1** (white), filled by RectFill before the frame is drawn (§2.3).

**2. Positive and negative gadgets**:
- **GadgetRender** = `Frame(Wg, Hg, r = 1, p = 0)` (inner **blue** line), whose
  **NextBorder** = `Frame(Wg, Hg, r = −1, p = 3)` (**orange** rectangle 1 pixel **outside**
  the gadget box).
  - Drawing order: blue line, then orange rectangle.
  - Both borders are alone in their allocation: 2 Borders per gadget.
- **SelectRender = NULL**.
- **Flags = GRELBOTTOM ($0008)**, plus **GRELRIGHT ($0010)** for the negative one. The highlight
  mode (bits 0–1) is 0, i.e. **GADGHCOMP**: the box is inverted on click.
- **Activation = $0101**, **GadgetType = $1001** (REQGADGET | BOOLGADGET).
- **GadgetID**: 1 for the positive one, 0 for the negative one.

**3. Texts**:
- **ReqText = `body`** and **GadgetText = `pos` / `neg`** are the caller's pointers,
  **used as is**. LeftEdge, TopEdge, pens, DrawMode, font and NextText are not
  modified: no write into these structures [O by absence].
  - With DiskCopy, the Continue and Cancel texts are in FrontPen 3 (orange) and BackPen 1, JAM1,
    at (6,3).
- **Gadget width** = pixel width of the **first IntuiText only** (NextText is not
  walked) + **12**. The measurement is done by TextLength:
  - with the `ITextFont` font if given (opened and set temporarily);
  - otherwise with the font of the **screen's RastPort** (`Screen.RastPort`, +$54);
  - the screen is that of `win`, otherwise the first WBENCHSCREEN-type screen in the list.
- **Gadget height** = font height + **6**. The height is:
  - `ITextFont->ta_YSize` if `ITextFont` is given;
  - otherwise `Screen.RastPort.TxHeight` (screen, +$8E);
  - otherwise a default value from IntuitionBase [S].
- **Gadget position**:
  - TopEdge = −(Height + 4), relative to the bottom of the requester (GRELBOTTOM);
  - **positive**: **LeftEdge = 14**;
  - **negative**: LeftEdge = −(Width + 13), relative to the right of the requester (GRELRIGHT).
  - With the orange rectangle at r = −1, this leaves 3 pixels of margin at the bottom and ~13 pixels
    left and right relative to the requester's edge (before its own frame at r = 1).

**4. NewWindow of the System Request window**:
- **LeftEdge = 0, TopEdge = 0** (ROM template, never modified) [O].
- **DetailPen / BlockPen = those of `win`** (`Window.DetailPen` +$62, `BlockPen` +$63) when
  `win` is supplied; otherwise **$FF / $FF**, i.e. the screen's default pens.
- Title, Screen and Type as in §5.2 item 1.

### 5.3 Alert fallback

When the window or the requester cannot be created:
- the Alert is **built from the IntuiTexts** of body, pos and neg (one line per text);
- it carries the ROM captions `"=LEFT BUTTON OK="` and `"=RIGHT BUTTON CANCEL="`;
- it is displayed by **DisplayAlert** (recoverable).
- The result of DisplayAlert (TRUE left button / FALSE right) is returned as 0 or 1.

### 5.4 FreeSysRequest(win)

**EndRequest(win->FirstRequest, win)**, then **FreeRemember(win->UserData, TRUE)**, then
**CloseWindow(win)**.

---

## 6. Use by DiskCopy 1.4 [O]

- **Libraries**: intuition and graphics, opened at version 0; no low-level requester
  function.
- **Window**: its own window (OpenWindow), with the screen title set by SetWindowTitles.
- **Prompts** ("Place %s %s" / "( FROM disk ) in drive %s"…):
  `AutoRequest(its window, body IntuiText, pos, neg, pflag, nflag, W, H)` with:
  - **pos = `"Continue"`** and **neg = `"Cancel"`** (IntuiText FrontPen 3, BackPen 1, JAM1,
    position (6,3));
  - **pflag = 0** and **nflag = CLOSEWINDOW ($200)**;
  - **W = 343 ($157), H = 72 ($48)**.
  - Return **FALSE** (Cancel, close or Amiga-B) ⇒ DiskCopy **exits** (code 10).
- **Other requester**: `"Unable to open icon.library"`, also via AutoRequest, with a
  different body.
- **IDCMP classes expected in the AutoRequest window**: **GADGETUP ($40)**, RAWKEY
  ($400), CLOSEWINDOW ($200, negative).

**Faithful minimum for DiskCopy [D]**:
- AutoRequest must open, on the screen of the window passed in, a **"System Request" window**
  of W × H (ACTIVATE, DEPTH, DRAG, SIZING) whose inner area contains:
  - a colour 1 background;
  - a frame;
  - the body text;
  - **two text gadgets** at the bottom: `Continue` on the left (ID 1) and `Cancel` on the right (ID 0).
- It must return TRUE on GADGETUP of the gadget with ID ≠ 0, and FALSE on ID 0 or CLOSEWINDOW.
- Going through Request only changes the internal structure. The appearance and the visible
  behaviour depend only on §5.2 and §5.1.

---

## 7. DiskCopy 1.4: sequence between OpenWindow and "Place SOURCE disk"

Case covered: launch from the Workbench, `sm_NumArgs = 2`, `ArgList[1] = { wa_Lock = root
of DF0:, wa_Name = "" }`, a single drive. The silent-exit conditions before the window
are in `workbench-task-v34.md` §7.9.1. All the steps below are **[O]** unless stated.

### 7.1 Call order

1. **intuition SetWindowTitles (−276)** (window, −1, `"DiskCopy"`).
2. **Resolution of the DESTINATION** (ArgList[1]).
   - With 2 arguments, source and destination designate the same WBArg, hence the same wa_Lock.
     DiskCopy then records "same disk" and skips the destination-specific checks.
   - Preliminary check: the name passed for the destination must be empty, otherwise silent
     exit. In the "same disk" case, this name is an internal (empty) buffer, not wa_Name.
     wa_Name is then only used for the source, as the device name (empty ⇒ search by task).
   - Calls, in order:
     1. **dos ParentDir (−210)** (wa_Lock); if it returns a value ≠ 0: UnLock, then exit;
     2. **dos IoErr (−132)**; if it returns ≠ 0, error then exit;
     3. **dos Info (−114)** (wa_Lock, 36-byte InfoData);
     4. **dos Examine (−102)** (wa_Lock, 260-byte FIB);
     5. **dos UnLock (−90)** (wa_Lock), then **wa_Lock := 0** in the WBArg.
   - Device search **without a system call and without Forbid**: direct walk of `dl_Root →
     rn_Info → di_DevInfo`, looking for the `dn_Type = 0` node whose `dn_Task` equals
     `id_VolumeNode → dol_Task` (§7.9.1 of workbench-task). Result: the name `"DF0:"`.
3. **Resolution of the SOURCE** on the **same** WBArg, whose **wa_Lock is now 0**:
   - no ParentDir/Info/Examine ("no lock" branch);
   - a possible trailing `':'` is removed from the (empty) name;
   - the label `"SOURCE disk"` is taken;
   - the device is searched for as above, **with the InfoData from step 2** (same task).
4. **dos DeviceProc (−174)** (`"DF0:"`) for the source, then for the destination. The two
   ports are compared to find out whether it is the same drive.
5. **ACTION_INHIBIT (31) packet, Arg1 = 1 (DOSTRUE)**, sent **directly** to the port returned by
   DeviceProc for the source. The destination only receives one if it is a different port. Detail
   in §7.2. If `dp_Res1 = 0`, error then exit.
6. **Geometry**: `dn_Startup` (+$1C, BPTR → FileSysStartupMsg) → `fssm_Environ` (+$08, BPTR
   → DosEnvec). Fields read:
   - `de_Surfaces` (+$0C);
   - `de_BlocksPerTrack` (+$14);
   - `de_Reserved` (+$18);
   - `de_LowCyl` (+$24);
   - `de_HighCyl` (+$28).
   Computations:
   - number of cylinders = HighCyl − LowCyl + 1;
   - cylinder size = BlocksPerTrack × 512 × Surfaces.
   Source and destination must have the same geometry, otherwise error then exit.
   **No protection against a null `dn_Startup` or `fssm_Environ`**: a null pointer would be
   dereferenced.
7. **exec AllocMem**(cylinder size, MEMF_CHIP|MEMF_CLEAR): verification buffer.
8. **Cylinder buffers**, with no call other than AllocMem and FreeMem:
   - an array of (cylinders + 1) pointers (MEMF_PUBLIC|CLEAR);
   - with a single drive, cylinders are allocated one by one (the first in CHIP|CLEAR, the
     following ones in PUBLIC|CLEAR) **until an allocation fails**, or until all
     cylinders are covered;
   - on the first failure, **the previous buffer is given back**, to leave some headroom;
   - the number of buffers is then balanced between the passes, and the surplus buffers are
     given back.
   - If no buffer could be allocated: **AutoRequest "Not enough memory…"** (Continue or
     Cancel), then a new attempt.
9. **Single drive with fewer than cylinders/4 buffers**:
   - all buffers are given back;
   - **AutoRequest "Notice: This will take N swaps."**;
   - reallocation;
   - the text "Diskcopy will take %d swaps." is **written into the window** (graphics Move and
     Text);
   - then **dos Delay (−198)(15)**.
   Otherwise this step is skipped.
10. **exec OpenDevice (−444)**(name = `fssm_Device` (+$04, BSTR), unit = `fssm_Unit` (+$00),
    52-byte IOExtTD created by CreateExtIO, **flags 0**), for the source then for the
    destination. A failure gives an error then exit. The flags in `fssm_Flags` are not
    used.
11. Preparation of the two requests:
    - `ln_Type` := **7 (NT_REPLYMSG)**;
    - `io_Error` := 0;
    - a private field receives `de_LowCyl`.
12. **exec CheckIO (−468)** (source request): it returns "completed" thanks to the NT_REPLYMSG set
    just before. Otherwise **WaitIO (−474)** would be called.
13. **exec DoIO (−456)** (source request, **io_Command = 9 (TD_MOTOR)**, **io_Length = 0**):
    **motor off, synchronous**.
14. Construction of the text "Place SOURCE disk ( FROM disk ) in drive DF0:", then **intuition
    AutoRequest (−348)** (§6).

**No other trackdisk command** (TD_CHANGESTATE, TD_PROTSTATUS, TD_ADDCHANGEINT,
TD_CHANGENUM…) is sent before this prompt. They come after the Continue reply.

### 7.2 ACTION_INHIBIT packet: exact form and wait [O]

- **Allocation**: **AllocMem(68, MEMF_PUBLIC)**, **without MEMF_CLEAR**. This represents a
  `StandardPacket`: 20-byte Message, then 48-byte DosPacket.
- **Fields filled in**:
  - `mn_Node.ln_Name` (+$0A) := address of the DosPacket (+$14);
  - `dp_Link` (+$14) := the Message;
  - **`dp_Port` (+$18) := `&FindTask(0)->pr_MsgPort`** (process +$5C);
  - **`dp_Type` (+$1C) := 31**;
  - **`dp_Arg1` (+$28) := 1** (inhibit) or 0 (end of inhibit, on exit).
- **Fields NOT filled in**: `mn_ReplyPort` (+$0E), `mn_Length`, `ln_Type` and the other
  arguments keep the **random contents** of the allocated memory.
- **Send**: **exec PutMsg (−366)** (handler port, message).
- **Wait**: **exec WaitPort (−384)** on **the DiskCopy process's `pr_MsgPort`**, then **exec
  Remove (−252)** of the message. There is **no** GetMsg: the message is simply removed from
  the port's list.
- **Result**: `dp_Res1` (+$20). Then FreeMem(68).

**⇒ Most likely blocking point [D]**: DiskCopy waits for the reply **only** on its
`pr_MsgPort`, and `mn_ReplyPort` contains garbage. The handler must therefore return the packet
**via `dp_Port`**, following the dos convention: PutMsg to `dp_Port`, after rewriting
`dp_Port` with its own port. If it replies with `ReplyMsg()`, which uses mn_ReplyPort, or if it
ignores ACTION_INHIBIT without replying, DiskCopy stays **blocked forever in WaitPort**. One
then gets exactly the observed symptom: window open and empty, no AutoRequest, the process
never ends.

### 7.3 Other waits that might never finish [D]

| Step | Wait | Blocking condition |
|---|---|---|
| 5 | WaitPort(pr_MsgPort) | no reply to ACTION_INHIBIT via `dp_Port` (§7.2) |
| 9 | dos Delay(15) | faulty timer.device or Delay (only on the "swaps" path) |
| 12 | WaitIO | only if CheckIO says "not completed", which does not happen since ln_Type = 7 is set just before |
| 13 | DoIO(TD_MOTOR) | trackdisk not replying to TD_MOTOR |
| 8 | AllocMem loop | loops only as long as allocations succeed, at most "cylinders" times; an AllocMem that never returns 0 beyond free memory would take everything, and the AutoRequest of step 14 could then fail for lack of memory |
| 6 | DosEnvec read | null `dn_Startup` / `fssm_Environ` ⇒ read at address 0, no blocking but with absurd values (possible division by 0 in the buffer balancing [S]) |

**Advised verification order**:
1. ACTION_INHIBIT reply via `dp_Port` to `pr_MsgPort`.
2. TD_MOTOR via DoIO.
3. Delay.
4. Memory left free after step 8: the real ROM leaves about one cylinder, i.e. 11 KB
   for a DD floppy.

---

## Clean-room review

- [x] No instruction sequence copied: only public layouts (Requester, Window,
  NewWindow, Gadget, IntuiText), constants (Flags, IDCMP, GadgetType, Activation), library
  calls (layers CreateBehindLayer −42, MoveLayerInFrontOf −168, DeleteLayer;
  graphics BltBitMapRastPort / RectFill; intuition DrawBorder / PrintIText; layers DeleteLayer −90) and behavioural rules.
- [x] Internal mechanisms (deferred event queue, codes 9/10/11) are described by their
  observable effect (REQSET/REQCLEAR), without transcription.
- [x] DiskCopy is described by its public calls and its data (texts, flags, sizes).
- [x] §7 (reviewed): sequence described by public calls (exec, dos, intuition, graphics,
  trackdisk), the form of the dos packet (StandardPacket fields) and the wait conditions.
  No instruction sequence copied.
- [x] §5.2.1 (reviewed): borders described by their parameters (count, pens, mode, list of the
  9 points as a formula), gadgets and texts by their public fields. No instruction sequence
  copied.
