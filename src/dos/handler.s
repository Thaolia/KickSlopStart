; src/dos/handler.s - floppy file-handler process (D3b), one per drive (DF0:, DF1:). Body of a Process (created
; by proc_create) that loops
; WaitPort/GetMsg on its pr_MsgPort and serves DOS packets: ACTION_FINDINPUT/READ/SEEK/END + LOCATE_OBJECT/
; FREE_LOCK/EXAMINE_OBJECT/EXAMINE_NEXT, relying on the OFS machinery (ofs_stream_* / ofs_name_to_block /
; ofs_fill_fib / ofs_dir_next). INTERNAL machinery (no user-facing dos.library = D3c).
;
; Protocol (docs/analysis/dos-v34-spec.md §2): msg->ln_Name -> DosPacket. On FINDINPUT (ARG1=BPTR FileHandle,
; ARG2=lock of the starting directory, ARG3=BSTR name) the handler allocates a STREAMING state (SS_*, ofs.i: a single
; AllocMem including the ioreq + a 512-byte block buffer), opens it via ofs_stream_open (resolves the path -> first
; data block, WITHOUT reading the file), sets fh_Arg1 = state in the FileHandle (BADDR(ARG1)), returns DOSTRUE. READ
; (ARG1=fh_Arg1, ARG2=dest, ARG3=len) reads INCREMENTALLY via ofs_stream_read (data block by data block, the cursor
; advances in the state; RES1=bytes, 0=EOF). SEEK repositions via ofs_stream_seek (returns the old position). END
; frees the state.
; REAL STREAMING: no more whole-file buffer -> no file size cap (O(1) footprint = 512 bytes per handle).
; Drive: the unit of the FileSysStartupMsg of the DeviceNode whose dn_Task is this process's port. Per-drive state
; (mounted volume, disk change, write context) lives in the handler context, published in tc_UserData (ofs.i).
; IMPLEMENTATION track ("clean"): analysis spec + exec AutoDocs. NO ROM reading.

                include "exec.i"
                include "ofs.i"
                include "dospkt.i"
                include "dos.i"
                include "disk.i"

                xdef    dos_handler
                xref    ofs_name_to_block    ; LOCATE_OBJECT: path -> block
                xref    ofs_fill_fib         ; EXAMINE_OBJECT: block -> FIB
                xref    ofs_dir_next         ; EXAMINE_NEXT: next directory entry
                xref    ofs_stream_open      ; FINDINPUT: opens a file for streaming
                xref    ofs_stream_read      ; READ: incremental read data block by data block
                xref    ofs_stream_seek      ; SEEK: repositions the streaming cursor
                xref    ow_create            ; OFS writing (ofswrite.s)
                xref    ow_delete
                xref    ow_rename
                xref    ow_setfield
                xref    ow_diskinfo
                xref    ow_inhibit
                xref    ws_open
                xref    ws_write
                xref    ws_close
                xref    ofs_read_block       ; hnd_bootclock: reading of the root block
                xref    timer_now            ; system time (exec/timer.s)
                xref    timer_setnow

ACTION_MORE_CACHE EQU 18             ; AddBuffers: adds buffers to the filesystem
ID_VALIDATING   EQU 81               ; InfoData.id_DiskState: no bitmap (no disk, or non-DOS disk)
IND_WRITEEVENT_C EQU 11              ; input.device
IE_SIZE         EQU 22               ; struct InputEvent
DT_DOS          EQU $444F5300        ; "DOS\0"
DT_NDOS         EQU $4E444F53        ; "NDOS": DOS boot block but invalid root block
DT_BAD          EQU $42414400        ; "BAD\0": block 0 unreadable

; handler context (allocated at its startup, pointer in tc_UserData; HC_TDIO and HC_OWCTX: ofs.i)
HC_VOLUME       EQU HC_OWCTX+4       ; BPTR: volume node of the floppy mounted in this drive | 0
HC_TMPORT       EQU HC_VOLUME+4      ; timer reply port (MP_SIZE, rounded)
HC_TMREQ        EQU HC_TMPORT+36     ; timerequest (40)
HC_INPORT       EQU HC_TMREQ+40      ; input.device reply port
HC_INIO         EQU HC_INPORT+36     ; IOStdReq input.device
HC_IEV          EQU HC_INIO+IOREQ_SZ ; InputEvent (IE_SIZE, rounded)
HC_SIGS         EQU HC_IEV+24        ; signals waited for: packet port | timer
HC_CHG          EQU HC_SIGS+4        ; TD_CHANGENUM at mount time
HC_DTYPE        EQU HC_CHG+4         ; type of the mounted disk (id_DiskType), -1: none
HC_MOUNTED      EQU HC_DTYPE+4       ; byte: a disk has been examined since the last ejection
HC_INHIB        EQU HC_MOUNTED+1     ; byte: ACTION_INHIBIT in progress
HC_TMOK         EQU HC_INHIB+1       ; byte: timer open, request pending
HC_INOK         EQU HC_TMOK+1        ; byte: input.device open
HC_SIZE         EQU HC_INOK+1
ACTION_INHIBIT  EQU 31               ; Arg1 = DOSTRUE: the disk is no longer accessed (DiskCopy, Format)
WS_MAGICV       EQU $57524954        ; head of a write state (ofswrite.s); a read state starts with an APTR
HND_NAMEBUF     EQU 112              ; C string of a name received as a BSTR (stack)

; dos_handler: process body. GPRs at zero on entry (AddTask frame) -> reload SysBase.
; a2 = pr_MsgPort (persistent); a3 = current Message; a4 = current DosPacket.
; Disk change (spec disk-change-v34 §2): woken by a packet or by a 1 s timer tick; on each wakeup
; hnd_check queries trackdisk (TD_CHANGESTATE / TD_CHANGENUM): ejection -> volume detached, DISKREMOVED;
; insertion -> volume found again (same name, same creation date) or created, DISKINSERTED.
dos_handler:
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a2
                lea     PR_MSGPORT(a2),a2    ; a2 = its own pr_MsgPort
                bsr     hnd_init
.hl:
                bsr     hnd_ctx
                beq.s   .hl_port             ; no context: packets only
                move.l  d0,a0
                move.l  HC_SIGS(a0),d0
                jsr     LVO_WAIT(a6)         ; packet or tick
                bsr     hnd_tick
                bsr     hnd_check
                bra.s   .hl_msg
.hl_port:
                move.l  a2,a0
                jsr     LVO_WAITPORT(a6)
.hl_msg:
                move.l  a2,a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .hl
                move.l  d0,a3                ; a3 = Message
                move.l  LN_NAME(a3),a4       ; a4 = DosPacket (convention: msg->ln_Name)
                clr.l   DP_RES2(a4)
                bsr     hnd_gate             ; lock or file of another volume, no disk: refused
                tst.l   d0
                bne     .refuse
                move.l  DP_TYPE(a4),d0
                cmp.l   #ACTION_FINDINPUT,d0
                beq     .findinput
                cmp.l   #ACTION_READ,d0
                beq     .read
                cmp.l   #ACTION_END,d0
                beq     .end
                cmp.l   #ACTION_SEEK,d0
                beq     .seek
                cmp.l   #ACTION_LOCATE_OBJECT,d0
                beq     .locate
                cmp.l   #ACTION_FREE_LOCK,d0
                beq     .freelock
                cmp.l   #ACTION_EXAMINE_OBJECT,d0
                beq     .examine
                cmp.l   #ACTION_EXAMINE_NEXT,d0
                beq     .exnext
                cmp.l   #ACTION_MORE_CACHE,d0
                beq     .morecache
                cmp.l   #ACTION_PARENT,d0
                beq     .parent
                cmp.l   #ACTION_COPY_DIR,d0
                beq     .copydir
                cmp.l   #ACTION_FINDOUTPUT,d0
                beq     .findoutput
                cmp.l   #ACTION_FINDUPDATE,d0
                beq     .findupdate
                cmp.l   #ACTION_WRITE,d0
                beq     .write
                cmp.l   #ACTION_DELETE_OBJECT,d0
                beq     .delete
                cmp.l   #ACTION_RENAME_OBJECT,d0
                beq     .rename
                cmp.l   #ACTION_CREATE_DIR,d0
                beq     .createdir
                cmp.l   #ACTION_SET_PROTECT,d0
                beq     .setprot
                cmp.l   #ACTION_SET_COMMENT,d0
                beq     .setcomment
                cmp.l   #ACTION_DISK_INFO,d0
                beq     .diskinfo
                cmp.l   #ACTION_INFO,d0
                beq     .info
                cmp.l   #ACTION_INHIBIT,d0
                beq     .inhibit
                move.l  #DOSFALSE,DP_RES1(a4)         ; unknown action
                move.l  #ERROR_ACTION_NOT_KNOWN,DP_RES2(a4)
                bra     .reply
.refuse:
                move.l  d0,DP_RES2(a4)
                move.l  #DOSFALSE,DP_RES1(a4)
                bra     .reply

.findinput:
                move.l  #SS_ALLOC,d0                 ; streaming state (fields + ioreq + 512-byte block buffer)
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .fi_fail
                move.l  d0,d6                        ; d6 = state (preserved by ofs_stream_open)
                ; convert the BSTR name (ARG3) into a C string on the stack for ofs_stream_open
                lea     -112(sp),sp
                move.l  DP_ARG3(a4),d0
                lsl.l   #2,d0                         ; BADDR(ARG3) = &BSTR (len + chars)
                move.l  d0,a0
                move.l  sp,a1
                moveq   #0,d1
                move.b  (a0)+,d1                      ; BCPL length
.fi_ncpy:
                tst.l   d1
                beq.s   .fi_ndone
                move.b  (a0)+,(a1)+
                subq.l  #1,d1
                bra.s   .fi_ncpy
.fi_ndone:
                clr.b   (a1)                          ; terminate as a C string
                move.l  DP_ARG2(a4),d0                ; lock of the starting directory (0 = root)
                bsr     hnd_lockkey                    ; d0 = directory block | 0
                move.l  sp,a0                         ; a0 = path, a1 = state
                move.l  d6,a1
                jsr     ofs_stream_open                ; d0 = 1/0 (resolves + inits cursor, WITHOUT reading the file)
                lea     112(sp),sp                    ; restore the stack (C string consumed)
                tst.l   d0
                beq.s   .fi_fail_state                ; not found / not a file
                move.l  DP_ARG1(a4),d0                ; FileHandle = BADDR(ARG1)
                lsl.l   #2,d0
                move.l  d0,a1
                move.l  d6,FH_ARG1(a1)                ; fh_Arg1 = key = streaming state
                move.l  d6,a1
                bsr     hnd_usevol
                move.l  d0,SS_VOL(a1)
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.fi_fail_state:
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)  ; not found -> IoErr (d3f depends on it)
                move.l  d6,a1
                move.l  #SS_ALLOC,d0
                jsr     LVO_FREEMEM(a6)
.fi_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                bra     .reply

.read:
                ifne    D3B_NO_READ
                clr.l   DP_RES1(a4)                   ; RED D3B_NO_READ: does NOT serve READ -> immediate EOF
                bra     .reply
                endc
                move.l  DP_ARG1(a4),a1
                cmp.l   #WS_MAGICV,(a1)
                beq     .rw_wrong                     ; file open for writing
                move.l  a2,-(sp)                       ; a2 = handler port: saved (ofs_stream_read takes dest in a2)
                move.l  DP_ARG1(a4),a1                ; a1 = streaming state
                move.l  DP_ARG2(a4),a2                ; a2 = dest
                move.l  DP_ARG3(a4),d0                ; d0 = len requested
                jsr     ofs_stream_read                ; d0 = bytes read (0 = EOF); cursor advanced in the state
                move.l  d0,DP_RES1(a4)
                move.l  (sp)+,a2                       ; restore the handler port
                bra     .reply

.seek:                                                ; Seek(ARG1=state, ARG2=position, ARG3=mode) -> RES1 = old pos
                ifne    HND_NO_SEEK
                move.l  DP_ARG1(a4),a1                ; RED HND_NO_SEEK: reads the state but does NOT reposition
                move.l  SS_POS(a1),DP_RES1(a4)
                bra     .reply
                endc
                move.l  DP_ARG1(a4),a1                ; a1 = state
                cmp.l   #WS_MAGICV,(a1)
                beq     .sk_err                       ; no repositioning while writing
                move.l  SS_POS(a1),d3                 ; d3 = old position (return value)
                move.l  DP_ARG2(a4),d1                ; position (signed)
                move.l  DP_ARG3(a4),d2                ; mode (OFFSET_BEGINNING -1 / CURRENT 0 / END 1)
                tst.l   d2
                blt.s   .sk_begin
                beq.s   .sk_current
                move.l  SS_SIZE(a1),d0                ; END: size + position
                add.l   d1,d0
                bra.s   .sk_bounds
.sk_begin:
                move.l  d1,d0                         ; BEGINNING: absolute position
                bra.s   .sk_bounds
.sk_current:
                move.l  d3,d0                         ; CURRENT: old + position
                add.l   d1,d0
.sk_bounds:
                tst.l   d0
                bmi.s   .sk_err
                cmp.l   SS_SIZE(a1),d0
                bhi.s   .sk_err                       ; outside [0, size]
                jsr     ofs_stream_seek                ; a1 = state, d0 = target -> repositions the cursor (dumb seek)
                move.l  d3,DP_RES1(a4)                ; returns the OLD position
                bra     .reply
.sk_err:
                move.l  #-1,DP_RES1(a4)
                move.l  #ERROR_SEEK_ERROR,DP_RES2(a4)
                bra     .reply

.locate:                                              ; Lock: (ARG2 BSTR name, ARG3 mode) -> RES1 = BPTR FileLock
                lea     -112(sp),sp                   ; BSTR name -> C string on the stack
                move.l  DP_ARG2(a4),d0
                lsl.l   #2,d0
                move.l  d0,a0                          ; BADDR(ARG2)
                move.l  sp,a1
                moveq   #0,d1
                move.b  (a0)+,d1                      ; BCPL length
.lo_ncpy:
                tst.l   d1
                beq.s   .lo_ndone
                move.b  (a0)+,(a1)+
                subq.l  #1,d1
                bra.s   .lo_ncpy
.lo_ndone:
                clr.b   (a1)                          ; C string terminated
                move.l  DP_ARG1(a4),d0                ; parent lock (0 = root)
                bsr     hnd_lockkey
                move.l  sp,a0                          ; a0 = name
                jsr     ofs_name_to_block              ; d0 = block | 0 (a6 = SysBase; preserves a2/a3/a4)
                lea     112(sp),sp
                tst.l   d0
                beq.s   .lo_fail                       ; object not found
                move.l  d0,d2                          ; d2 = block (preserved by AllocMem)
                move.l  #FL_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .lo_fail                       ; no RAM
                move.l  d0,a0                          ; a0 = FileLock
                move.l  d2,FL_KEY(a0)                 ; locked block
                move.l  DP_ARG3(a4),FL_ACCESS(a0)     ; mode (SHARED/EXCLUSIVE)
                move.l  a2,FL_TASK(a0)                ; handler port (= our pr_MsgPort) -> source for UnLock/Examine
                bsr     hnd_usevol
                move.l  d0,FL_VOLUME(a0)               ; volume node of the mounted disk (counted)
                move.l  a0,d1                          ; FL_LINK/cursor = 0 (MEMF_CLEAR)
                lsr.l   #2,d1                          ; BPTR(lock)
                move.l  d1,DP_RES1(a4)
                bra     .reply
.lo_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)
                bra     .reply

.freelock:                                            ; UnLock: (ARG1 BPTR lock) -> frees
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .frl_ok                        ; lock 0 -> no-op
                move.l  d0,a1
                move.l  FL_VOLUME(a1),d0
                bsr     hnd_unusevol
                move.l  #FL_SIZEOF,d0
                jsr     LVO_FREEMEM(a6)
.frl_ok:
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

.examine:                                             ; Examine: (ARG1 BPTR lock, ARG2 BPTR fib) -> fills the FIB
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .ex_fail
                move.l  d0,a0                          ; a0 = FileLock
                move.l  FL_KEY(a0),d0                 ; block of the locked object
                clr.l   FLP_BUCKET(a0)                ; reset the enumeration cursor (Examine -> start)
                clr.l   FLP_CHAIN(a0)
                move.l  DP_ARG2(a4),d1
                lsl.l   #2,d1
                move.l  d1,a1                          ; a1 = fib
                jsr     ofs_fill_fib                   ; d0 = 1/0 (preserves a2/a3/a4/a6)
                tst.l   d0
                beq.s   .ex_fail
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.ex_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)
                bra     .reply

.exnext:                                              ; ExNext: (ARG1 BPTR lock, ARG2 BPTR fib) -> next entry
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .exn_end
                move.l  d0,a0                          ; a0 = FileLock
                move.l  FL_KEY(a0),d0                 ; directory block
                move.l  FLP_BUCKET(a0),d1             ; bucket cursor
                move.l  FLP_CHAIN(a0),d2              ; chain cursor
                move.l  DP_ARG2(a4),d3
                lsl.l   #2,d3
                move.l  d3,a1                          ; a1 = fib
                move.l  a0,-(sp)                       ; ofs_dir_next does NOT preserve a0 -> save the lock
                jsr     ofs_dir_next                   ; d0=found, d1=updated bucket, d2=updated chain (preserves a2-a5)
                move.l  (sp)+,a0
                move.l  d1,FLP_BUCKET(a0)             ; write the cursor back into the lock
                move.l  d2,FLP_CHAIN(a0)
                tst.l   d0
                beq.s   .exn_end
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.exn_end:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_NO_MORE_ENTRIES,DP_RES2(a4)
                bra     .reply

.copydir:                                            ; DupLock: (ARG1 BPTR lock) -> new lock, same block
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                tst.l   d0
                bne.s   .cd_key
                move.l  #OFS_ROOTBLK,d0                ; lock 0 = root
.cd_key:
                move.l  d0,d2
                bra.s   .pa_alloc
.parent:                                             ; ParentDir: (ARG1 BPTR lock) -> lock of the parent | 0 (root)
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                lea     hnd_slash(pc),a0               ; "/" = parent of the starting directory
                jsr     ofs_name_to_block
                tst.l   d0
                beq.s   .pa_root                       ; parent of the root: 0 without error
                move.l  d0,d2
.pa_alloc:                                             ; d2 = block -> new shared FileLock
                move.l  #FL_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .pa_root
                move.l  d0,a0
                move.l  d2,FL_KEY(a0)
                move.l  #SHARED_LOCK,FL_ACCESS(a0)
                move.l  a2,FL_TASK(a0)
                bsr     hnd_usevol
                move.l  d0,FL_VOLUME(a0)
                move.l  a0,d0
                lsr.l   #2,d0
                move.l  d0,DP_RES1(a4)
                bra     .reply
.pa_root:
                clr.l   DP_RES1(a4)
                bra     .reply

.inhibit:                                            ; (ARG1: DOSTRUE = inhibit, 0 = release)
                move.l  DP_ARG1(a4),d0
                jsr     ow_inhibit                     ; bitmap written / forgotten
                bsr     hnd_ctx
                beq.s   .ih_ok
                move.l  d0,a0
                tst.l   DP_ARG1(a4)
                beq.s   .ih_off
                tst.b   HC_INHIB(a0)
                bne.s   .ih_ok
                st      HC_INHIB(a0)                   ; volume detached as on ejection, without an event
                move.l  a3,-(sp)
                move.l  a0,a3
                moveq   #0,d0
                bsr     hnd_eject
                move.l  #$42555359,HC_DTYPE(a3)        ; "BUSY"
                move.l  (sp)+,a3
                bra.s   .ih_ok
.ih_off:
                tst.b   HC_INHIB(a0)
                beq.s   .ih_ok
                sf      HC_INHIB(a0)                   ; full remount on the next wakeup
                sf      HC_MOUNTED(a0)
                move.l  #-1,HC_DTYPE(a0)
.ih_ok:
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

.morecache:                                          ; AddBuffers: no FS block cache (trackdisk keeps the track)
                move.l  #DOSTRUE,DP_RES1(a4)          ; -> accepted without effect
                bra     .reply

.end:
                move.l  DP_ARG1(a4),a1                ; a1 = streaming state (a single AllocMem)
                cmp.l   #WS_MAGICV,(a1)
                beq.s   .end_w
                move.l  SS_VOL(a1),d0
                bsr     hnd_unusevol
                move.l  #SS_ALLOC,d0
                jsr     LVO_FREEMEM(a6)               ; free the state (ioreq + block buffer included)
                move.l  #DOSTRUE,DP_RES1(a4)
.reply:                                              ; returnpkt: to dp_Port (mn_ReplyPort may
                move.l  DP_PORT(a4),a0                ; not be filled in: DiskCopy), which receives
                move.l  a2,DP_PORT(a4)                ; the handler port in return
                move.l  a3,a1
                jsr     LVO_PUTMSG(a6)
                bra     .hl_msg
.end_w:
                move.l  WS_VOL(a1),d0
                bsr     hnd_unusevol
                jsr     ws_close                       ; data, extension, header, bitmap written; state freed
                move.l  d0,DP_RES1(a4)
                bne.s   .reply
                move.l  #ERROR_DISK_WRITE_PROTECTED,DP_RES2(a4)
                bra.s   .reply
.rw_wrong:
                move.l  #-1,DP_RES1(a4)
                move.l  #ERROR_OBJECT_WRONG_TYPE,DP_RES2(a4)
                bra.s   .reply

; --- writing (ofswrite.s) ---
.findupdate:                                         ; existing file -> read; otherwise created like FINDOUTPUT
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG3(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG2(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                jsr     ofs_name_to_block
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                bne     .findinput
.findoutput:                                         ; (ARG1 fh, ARG2 lock, ARG3 BSTR name): file created or replaced
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG3(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG2(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                jsr     ws_open                        ; d0 = state | 0, d1 = error
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                beq     .w_fail
                move.l  DP_ARG1(a4),d1
                lsl.l   #2,d1
                move.l  d1,a1
                move.l  d0,FH_ARG1(a1)
                move.l  d0,a1
                bsr     hnd_usevol
                move.l  d0,WS_VOL(a1)
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.write:                                              ; (ARG1 state, ARG2 data, ARG3 length) -> RES1 = length | -1
                move.l  DP_ARG1(a4),a1
                cmp.l   #WS_MAGICV,(a1)
                bne     .rw_wrong                     ; file open for reading
                move.l  DP_ARG2(a4),a0
                move.l  DP_ARG3(a4),d0
                jsr     ws_write
                move.l  d0,DP_RES1(a4)
                move.l  d1,DP_RES2(a4)
                bra     .reply
.delete:                                             ; (ARG1 lock, ARG2 BSTR name)
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG2(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                jsr     ow_delete
                bra     .w_res
.rename:                                             ; (ARG1 lock, ARG2 BSTR old, ARG3 lock, ARG4 BSTR new)
                lea     -2*HND_NAMEBUF(sp),sp
                move.l  DP_ARG2(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG4(a4),d0
                lea     HND_NAMEBUF(sp),a1
                bsr     hnd_cstr
                move.l  DP_ARG3(a4),d0
                bsr     hnd_lockkey
                move.l  d0,d1
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                lea     HND_NAMEBUF(sp),a1
                jsr     ow_rename
                lea     HND_NAMEBUF(sp),sp
                bra     .w_res
.createdir:                                          ; (ARG1 lock, ARG2 BSTR name) -> RES1 = lock of the directory
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG2(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                moveq   #OFS_ST_USERDIR,d1
                jsr     ow_create
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                beq.s   .w_fail
                move.l  d0,d2
                bra     .pa_alloc
.setprot:                                            ; (ARG2 lock, ARG3 BSTR name, ARG4 mask)
                moveq   #0,d1
                bra.s   .setfield
.setcomment:                                         ; (ARG2 lock, ARG3 BSTR name, ARG4 BSTR comment)
                moveq   #1,d1
.setfield:
                lea     -HND_NAMEBUF(sp),sp
                move.l  d1,-(sp)
                move.l  DP_ARG3(a4),d0
                lea     4(sp),a1
                bsr     hnd_cstr
                move.l  DP_ARG2(a4),d0
                bsr     hnd_lockkey
                move.l  (sp)+,d1
                move.l  sp,a0
                move.l  DP_ARG4(a4),d2
                jsr     ow_setfield
.w_res:
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                beq.s   .w_fail
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.w_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  d1,DP_RES2(a4)
                bra     .reply
.info:                                               ; (ARG1 lock, ARG2 BPTR InfoData)
                move.l  DP_ARG2(a4),d0
                bra.s   .di_go
.diskinfo:                                           ; (ARG1 BPTR InfoData)
                move.l  DP_ARG1(a4),d0
.di_go:
                lsl.l   #2,d0
                move.l  d0,a0
                bsr     hnd_ctx
                beq.s   .di_none
                move.l  d0,a1
                move.l  HC_VOLUME(a1),d1
                beq.s   .di_none
                move.l  d1,a1
                jsr     ow_diskinfo
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.di_none:                                            ; no volume: "validating" state, current type
                moveq   #8,d0
.di_clr:
                clr.l   (a0)+
                dbra    d0,.di_clr
                lea     -36(a0),a0
                move.l  #ID_VALIDATING,8(a0)
                moveq   #-1,d1
                bsr     hnd_ctx
                beq.s   .di_ty
                move.l  d0,a1
                move.l  HC_DTYPE(a1),d1
.di_ty:
                move.l  d1,24(a0)
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

; hnd_bootclock(a6 = SysBase): time setting at mount time (spec boot-clock-v34): the system time takes the more
; recent of the two dates of the root block (root directory, longs 105-107; disk, longs 118-120) if it is still
; on the first day (clock never set) and earlier than that date; never moved backwards. Called on every mount of a
; DOS disk. Preserves everything.
HND_ROOTDATE    EQU 420              ; modification DateStamp of the root directory
HND_DISKDATE    EQU 472              ; modification DateStamp of the disk
hnd_bootclock:
                movem.l d0-d7/a0-a3,-(sp)
                lea     EB_DEVICELIST(a6),a0
                lea     hnd_tdname(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .bc_ret
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .bc_ret
                move.l  d0,a3
                move.l  #OFS_ROOTBLK,d0
                jsr     ofs_read_block
                tst.l   d0
                beq.s   .bc_free             ; no disk
                lea     IOREQ_SZ(a3),a0
                moveq   #0,d0                ; OFS checksum: sum of the 128 longs is zero
                moveq   #OFS_BSIZE/4-1,d1
.bc_sum:
                add.l   (a0)+,d0
                dbra    d1,.bc_sum
                tst.l   d0
                bne.s   .bc_free
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a0)
                bne.s   .bc_free
                lea     HND_ROOTDATE(a0),a1
                bsr.s   hnd_dssecs
                move.l  d0,d2                ; d2/d3 = date retained (seconds, us)
                move.l  d1,d3
                lea     IOREQ_SZ+HND_DISKDATE(a3),a1
                bsr.s   hnd_dssecs
                cmp.l   d2,d0
                bls.s   .bc_max
                move.l  d0,d2
                move.l  d1,d3
.bc_max:
                jsr     timer_now            ; d0/d1 = system time
                cmp.l   #86400,d0
                bhs.s   .bc_free             ; already set (past the first day)
                cmp.l   d2,d0
                bhi.s   .bc_free
                blo.s   .bc_set
                cmp.l   d3,d1
                bhs.s   .bc_free
.bc_set:
                move.l  d2,d0
                move.l  d3,d1
                jsr     timer_setnow
.bc_free:
                move.l  a3,a1
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
.bc_ret:
                movem.l (sp)+,d0-d7/a0-a3
                rts

; hnd_dssecs(a1 = DateStamp [days, minutes, ticks]) -> d0 = seconds, d1 = us (ticks bounded to 16 bits).
hnd_dssecs:
                move.l  (a1),d0
                mulu    #1440,d0             ; days -> minutes
                add.l   4(a1),d0
                move.l  d0,d1                ; x 60 = x 64 - x 4
                lsl.l   #6,d0
                lsl.l   #2,d1
                sub.l   d1,d0
                move.l  8(a1),d1
                and.l   #$0000FFFF,d1
                divu    #50,d1               ; d1 = remainder: seconds
                add.w   d1,d0
                bcc.s   .ds_nc
                add.l   #$10000,d0
.ds_nc:
                clr.w   d1
                swap    d1
                mulu    #20000,d1            ; remainder (ticks) -> us
                rts
hnd_tdname:
                dc.b    "trackdisk.device",0
hnd_tmname:
                dc.b    "timer.device",0
hnd_inname:
                dc.b    "input.device",0
                even


; hnd_init(a2 = pr_MsgPort, a6): context (tc_UserData), trackdisk opened on the drive of the handler, timer port
; and request (UNIT_VBLANK, 1 s), input.device, then first mount. Without memory: the handler runs anyway, without
; a disk (no volume is ever mounted). Preserves d2-d7/a2-a6.
hnd_init:
                movem.l d2/a3,-(sp)
                moveq   #0,d2
                move.b  MP_SIGBIT(a2),d0
                bset    d0,d2                         ; d2 = signal of the packet port
                move.l  #HC_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .in_ret
                move.l  d0,a3
                move.l  EB_THISTASK(a6),a0
                move.l  a3,TC_USERDATA(a0)
                move.l  d2,HC_SIGS(a3)
                move.l  #-1,HC_DTYPE(a3)
                bsr     hnd_unit                      ; d0 = unit
                lea     HC_TDIO(a3),a1
                lea     hnd_tdname(pc),a0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)            ; failure: io_Device = 0, the drive is never examined
                lea     HC_TMPORT(a3),a0
                bsr     hnd_port
                beq.s   .in_input
                or.l    d0,HC_SIGS(a3)
                lea     HC_TMREQ(a3),a1
                lea     HC_TMPORT(a3),a0
                move.l  a0,MN_REPLYPORT(a1)
                lea     hnd_tmname(pc),a0
                moveq   #UNIT_VBLANK,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                tst.l   d0
                bne.s   .in_input
                st      HC_TMOK(a3)
                bsr     hnd_arm
.in_input:
                lea     HC_INPORT(a3),a0
                bsr     hnd_port
                beq.s   .in_mount
                lea     HC_INIO(a3),a1
                lea     HC_INPORT(a3),a0
                move.l  a0,MN_REPLYPORT(a1)
                lea     hnd_inname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                tst.l   d0
                bne.s   .in_mount
                st      HC_INOK(a3)
.in_mount:
                bsr     hnd_check
.in_ret:
                movem.l (sp)+,d2/a3
                rts
; hnd_unit(a2 = port, a6) -> d0 = trackdisk unit of the DeviceNode served by this handler (dn_Task = port), from
; its FileSysStartupMsg; 0 if none is found. Clobbers a0.
hnd_unit:
                bsr     hnd_devinfo
                move.l  (a0),d0
.un_lp:
                lsl.l   #2,d0
                beq.s   .un_ret
                move.l  d0,a0
                move.l  DN_NEXT(a0),d0
                tst.l   DN_TYPE(a0)                   ; DLT_DEVICE
                bne.s   .un_lp
                cmp.l   DN_TASK(a0),a2
                bne.s   .un_lp
                move.l  DN_STARTUP(a0),d0
                lsl.l   #2,d0
                beq.s   .un_ret
                move.l  d0,a0
                move.l  FSSM_UNIT(a0),d0
.un_ret:
                rts
; hnd_ctx(a6) -> d0 = context of this handler | 0 (Z = 1). Clobbers a1.
hnd_ctx:
                move.l  EB_THISTASK(a6),a1
                move.l  TC_USERDATA(a1),d0
                rts
; hnd_port(a0 = MsgPort to set up, a6) -> d0 = mask of its signal (0: no free signal). Clobbers d1/a0/a1.
hnd_port:
                move.l  a0,-(sp)
                moveq   #-1,d0
                jsr     LVO_ALLOCSIGNAL(a6)
                move.l  (sp)+,a0
                tst.b   d0
                bmi.s   .po_none
                move.b  #NT_MSGPORT,LN_TYPE(a0)
                clr.b   MP_FLAGS(a0)                  ; PA_SIGNAL
                move.b  d0,MP_SIGBIT(a0)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a0)
                lea     MP_MSGLIST(a0),a1             ; empty list
                move.l  a1,8(a1)
                addq.l  #4,a1
                clr.l   (a1)
                move.l  a1,-(a1)
                moveq   #0,d1
                bset    d0,d1
                move.l  d1,d0
                rts
.po_none:
                moveq   #0,d0
                rts
; hnd_arm(a3 = context, a6): one-second timer request, asynchronous. Clobbers d0/d1/a0/a1.
hnd_arm:
                lea     HC_TMREQ(a3),a1
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                move.l  #1,TV_SECS(a1)
                clr.l   TV_SECS+4(a1)
                jmp     LVO_SENDIO(a6)
; hnd_tick(a6): timer reply received -> request re-armed. Preserves d2-d7/a2-a6.
hnd_tick:
                move.l  a3,-(sp)
                bsr     hnd_ctx
                beq.s   .tk_ret
                move.l  d0,a3
                tst.b   HC_TMOK(a3)
                beq.s   .tk_ret
                lea     HC_TMPORT(a3),a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .tk_ret
                bsr.s   hnd_arm
.tk_ret:
                move.l  (sp)+,a3
                rts

; hnd_tdcmd(d0.w = command, a3 = context, a6) -> d0 = io_Actual. Clobbers d1/a0/a1.
hnd_tdcmd:
                lea     HC_TDIO(a3),a1
                move.w  d0,IO_COMMAND(a1)
                move.b  #IOF_QUICK,IO_FLAGS(a1)
                clr.l   IO_ACTUAL(a1)
                move.l  a6,-(sp)
                move.l  IO_DEVICE(a1),a6
                jsr     -30(a6)              ; BeginIO
                move.l  (sp)+,a6
                move.l  HC_TDIO+IO_ACTUAL(a3),d0
                rts

; hnd_check(a2 = handler port, a6): ejection or insertion since the last pass (spec disk-change-v34 §2.1).
; Mounted: disk absent or different change counter -> ejection. Not mounted and disk present -> mount.
; Nothing during an inhibit. Preserves d2-d7/a2-a6.
hnd_check:
                movem.l d2/a3,-(sp)
                bsr     hnd_ctx
                beq.s   .ck_ret
                move.l  d0,a3
                tst.l   HC_TDIO+IO_DEVICE(a3)
                beq.s   .ck_ret
                tst.b   HC_INHIB(a3)
                bne.s   .ck_ret
                moveq   #TD_CHANGESTATE,d0
                bsr     hnd_tdcmd
                move.l  d0,d2                         ; d2 = 0: disk present
                tst.b   HC_MOUNTED(a3)
                beq.s   .ck_in
                tst.l   d2
                bne.s   .ck_out
                moveq   #TD_CHANGENUM,d0
                bsr     hnd_tdcmd
                cmp.l   HC_CHG(a3),d0
                beq.s   .ck_ret
.ck_out:
                moveq   #1,d0
                bsr     hnd_eject
                tst.l   d2
                bne.s   .ck_ret
.ck_in:
                tst.l   d2
                bne.s   .ck_ret
                bsr     hnd_mount
.ck_ret:
                movem.l (sp)+,d2/a3
                rts

; hnd_mount(a2 = port, a3 = context, a6): examines the inserted disk (block 0 then root block, spec §2.2.2 and §2.5).
; DOS disk: volume node with the same name and creation date reactivated, otherwise created at the head of the
; DosList; it becomes HC_VOLUME, bitmap forgotten, time set. Then DISKINSERTED, DOS disk or not. Preserves d2-d7/a2-a6.
hnd_mount:
                movem.l d2/a2-a4,-(sp)
                move.l  a2,a4                         ; a4 = handler port
                st      HC_MOUNTED(a3)
                move.l  HC_TDIO+IO_DEVICE(a3),a2
                moveq   #0,d0
                move.l  a3,-(sp)
                lea     HC_TDIO(a3),a3
                jsr     ofs_read_block
                move.l  (sp)+,a3
                move.l  #DT_BAD,d2
                tst.l   d0
                beq     .mo_type
                move.l  HC_TDIO+IOREQ_SZ(a3),d2       ; first long of block 0: "DOS\0" only (OFS)
                cmp.l   #DT_DOS,d2
                bne     .mo_type
                move.l  #DT_NDOS,d2
                move.l  #OFS_ROOTBLK,d0
                move.l  a3,-(sp)
                lea     HC_TDIO(a3),a3
                jsr     ofs_read_block
                move.l  (sp)+,a3
                tst.l   d0
                beq     .mo_type
                lea     HC_TDIO+IOREQ_SZ(a3),a0       ; root block checks
                moveq   #0,d0
                moveq   #OFS_BSIZE/4-1,d1
.mo_sum:
                add.l   (a0)+,d0
                dbra    d1,.mo_sum
                tst.l   d0
                bne     .mo_type
                lea     HC_TDIO+IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne     .mo_type
                tst.l   4(a0)                         ; header key
                bne     .mo_type
                cmp.l   #72,OFSB_HTSIZE(a0)
                bne     .mo_type
                cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a0)
                bne     .mo_type
                moveq   #0,d0
                move.b  OFSB_NAME(a0),d0
                beq     .mo_type
                cmp.b   #30,d0
                bhi     .mo_type
                move.l  #DT_DOS,d2
                bsr     hnd_findvol                   ; d0 = BPTR of the node (reactivated or created) | 0
                move.l  d0,HC_VOLUME(a3)
                moveq   #0,d0
                jsr     ow_inhibit                    ; bitmap of the old disk forgotten
                bsr     hnd_bootclock
.mo_type:
                move.l  d2,HC_DTYPE(a3)
                moveq   #TD_CHANGENUM,d0
                bsr     hnd_tdcmd
                move.l  d0,HC_CHG(a3)
                moveq   #IECLASS_DISKINSERTED,d0
                bsr     hnd_event
                movem.l (sp)+,d2/a2-a4
                rts

; hnd_findvol(a3 = context (root block at HC_TDIO+IOREQ_SZ), a4 = port, a6) -> d0 = BPTR of the volume node | 0:
; DLT_VOLUME node with the same name (case-insensitive) and the same creation date (longs 121..123): dl_Task := port;
; otherwise a new node at the head of the DosList (date, name, dl_Task; dl_Lock, dl_LockList and dl_DiskType at 0).
; Under Forbid. Clobbers d0/d1/a0/a1.
HND_CDATE       EQU 484              ; root block: creation date of the disk (longs 121..123)
hnd_findvol:
                movem.l d2/a2,-(sp)
                jsr     LVO_FORBID(a6)
                bsr     hnd_devinfo                   ; a0 = &di_DevInfo
                move.l  (a0),d2
.fv_lp:
                lsl.l   #2,d2
                beq.s   .fv_new
                move.l  d2,a2
                cmp.l   #DLT_VOLUME,DN_TYPE(a2)
                bne.s   .fv_nx
                lea     HC_TDIO+IOREQ_SZ+HND_CDATE(a3),a0
                lea     DOL_VOLDATE(a2),a1
                cmpm.l  (a0)+,(a1)+
                bne.s   .fv_nx
                cmpm.l  (a0)+,(a1)+
                bne.s   .fv_nx
                cmpm.l  (a0)+,(a1)+
                bne.s   .fv_nx
                move.l  DN_NAME(a2),d0
                lsl.l   #2,d0
                move.l  d0,a0
                lea     HC_TDIO+IOREQ_SZ+OFSB_NAME(a3),a1
                bsr     hnd_bstreq
                beq.s   .fv_found
.fv_nx:
                move.l  DN_NEXT(a2),d2
                bra.s   .fv_lp
.fv_found:
                move.l  a4,DN_TASK(a2)
                clr.l   DOL_LOCKLIST(a2)
                bra.s   .fv_ret
.fv_new:
                move.l  #DOL_NODESIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                move.l  d0,a2
                tst.l   d0
                beq.s   .fv_none
                move.l  #DLT_VOLUME,DN_TYPE(a2)
                move.l  a4,DN_TASK(a2)
                lea     HC_TDIO+IOREQ_SZ+HND_CDATE(a3),a0
                lea     DOL_VOLDATE(a2),a1
                move.l  (a0)+,(a1)+
                move.l  (a0)+,(a1)+
                move.l  (a0)+,(a1)+
                lea     HC_TDIO+IOREQ_SZ+OFSB_NAME(a3),a0
                lea     DN_SIZEOF(a2),a1              ; BSTR of the name right after the node
                move.l  a1,d0
                lsr.l   #2,d0
                move.l  d0,DN_NAME(a2)
                moveq   #0,d0
                move.b  (a0),d0                       ; length (1..30, checked)
.fv_cp:
                move.b  (a0)+,(a1)+
                dbra    d0,.fv_cp
                bsr     hnd_devinfo
                move.l  (a0),DN_NEXT(a2)
                move.l  a2,d0
                lsr.l   #2,d0
                move.l  d0,(a0)
.fv_ret:
                move.l  a2,d0
                lsr.l   #2,d0
.fv_none:
                jsr     LVO_PERMIT(a6)
                movem.l (sp)+,d2/a2
                rts
; hnd_devinfo -> a0 = &DosInfo.di_DevInfo. Clobbers d0.
hnd_devinfo:
                move.l  DOS_DOSBASE,a0
                move.l  DL_ROOT(a0),a0
                move.l  RN_INFO(a0),d0
                lsl.l   #2,d0
                move.l  d0,a0
                lea     DI_DEVINFO(a0),a0
                rts
; hnd_bstreq(a0, a1 = BSTR) -> Z = 1 if equal ignoring case (ASCII). Clobbers d0/d1/a0/a1.
hnd_bstreq:
                move.l  d2,-(sp)
                moveq   #0,d2
                move.b  (a0)+,d2
                cmp.b   (a1)+,d2
                bne.s   .be_ret
                bra.s   .be_nx
.be_lp:
                move.b  (a0)+,d0
                move.b  (a1)+,d1
                bsr.s   .be_up
                exg     d0,d1
                bsr.s   .be_up
                cmp.b   d0,d1
                bne.s   .be_ret
.be_nx:
                dbra    d2,.be_lp
                moveq   #0,d0                         ; Z = 1
.be_ret:
                movem.l (sp)+,d2                      ; (movem does not touch the condition codes)
                rts
.be_up:
                cmp.b   #'a',d0
                blo.s   .bu_r
                cmp.b   #'z',d0
                bhi.s   .bu_r
                sub.b   #'a'-'A',d0
.bu_r:
                rts

; hnd_eject(d0 = 1: emit DISKREMOVED, a3 = context, a6): current volume detached (spec §2.2.1): with no lock or
; open file, its node leaves the DosList and is freed; otherwise dl_Task := 0 (the node stays). Bitmap forgotten.
; Preserves d2-d7/a2-a6.
hnd_eject:
                movem.l d2/a2,-(sp)
                move.l  d0,d2
                moveq   #0,d0
                jsr     ow_inhibit
                sf      HC_MOUNTED(a3)
                move.l  #-1,HC_DTYPE(a3)
                move.l  HC_VOLUME(a3),d0
                clr.l   HC_VOLUME(a3)
                lsl.l   #2,d0
                beq.s   .ej_ev
                move.l  d0,a2
                jsr     LVO_FORBID(a6)
                tst.l   DOL_USE(a2)
                bne.s   .ej_keep
                bsr     hnd_devinfo                   ; removal from the DosList
.ej_find:
                move.l  (a0),d0
                lsl.l   #2,d0
                beq.s   .ej_free
                cmp.l   d0,a2
                beq.s   .ej_unlink
                move.l  d0,a0                         ; DN_NEXT = 0
                bra.s   .ej_find
.ej_unlink:
                move.l  DN_NEXT(a2),(a0)
.ej_free:
                jsr     LVO_PERMIT(a6)
                move.l  a2,a1
                move.l  #DOL_NODESIZE,d0
                jsr     LVO_FREEMEM(a6)
                bra.s   .ej_ev
.ej_keep:
                clr.l   DN_TASK(a2)
                jsr     LVO_PERMIT(a6)
.ej_ev:
                tst.l   d2
                beq.s   .ej_ret
                moveq   #IECLASS_DISKREMOVED,d0
                bsr     hnd_event
.ej_ret:
                movem.l (sp)+,d2/a2
                rts

; hnd_event(d0.b = ie_Class, a3 = context, a6): null InputEvent of this class written into input.device
; (IND_WRITEEVENT): intuition turns it into DISKINSERTED / DISKREMOVED. Clobbers d0/d1/a0/a1.
hnd_event:
                tst.b   HC_INOK(a3)
                beq.s   .ev_ret
                lea     HC_IEV(a3),a0
                clr.l   (a0)
                clr.l   4(a0)
                clr.l   8(a0)
                clr.l   12(a0)
                clr.l   16(a0)
                clr.w   20(a0)
                move.b  d0,4(a0)                      ; ie_Class
                lea     HC_INIO(a3),a1
                move.w  #IND_WRITEEVENT_C,IO_COMMAND(a1)
                move.l  a0,IO_DATA(a1)
                move.l  #IE_SIZE,IO_LENGTH(a1)
                jsr     LVO_DOIO(a6)
.ev_ret:
                rts

; hnd_gate(a4 = DosPacket) -> d0 = 0 if the packet can be served, otherwise the error code (spec §2.4): a lock or
; a file of a volume other than the mounted disk -> 218 (ERROR_DEVICE_NOT_MOUNTED); an action on the root
; without a disk -> 226 (ERROR_NO_DISK), non-DOS disk -> 225. Closes, UnLock, disk Info and inhibit always
; pass. Clobbers d1/a0/a1.
hnd_gate:
                move.l  DP_TYPE(a4),d0
                lea     hnd_gtab(pc),a0
.gt_lp:
                move.w  (a0)+,d1
                beq.s   .gt_ok                        ; action with no lock to check
                cmp.w   d1,d0
                beq.s   .gt_hit
                addq.l  #2,a0
                bra.s   .gt_lp
.gt_hit:
                moveq   #0,d1                         ; d1 = mounted volume | 0
                bsr     hnd_ctx
                beq.s   .gt_vol
                move.l  d0,a1
                move.l  HC_VOLUME(a1),d1
.gt_vol:
                move.w  (a0),d0                       ; argument offsets (high byte, low byte; 0 = none)
                tst.b   d0
                bmi.s   .gt_state
                bsr.s   .gt_arg
                bne.s   .gt_ret
                lsr.w   #8,d0
                bsr.s   .gt_arg
                bne.s   .gt_ret
.gt_ok:
                moveq   #0,d0
.gt_ret:
                rts
.gt_state:                                            ; READ/WRITE/SEEK: ARG1 = state of an open file
                move.l  DP_ARG1(a4),a0
                move.l  SS_VOL(a0),d0
                cmp.l   #WS_MAGICV,(a0)
                bne.s   .gs_cmp
                move.l  WS_VOL(a0),d0
.gs_cmp:
                tst.l   d1
                beq.s   .gt_218
                cmp.l   d1,d0
                beq.s   .gt_ok
.gt_218:
                move.l  d0,HND_REFVOL                 ; volume requested by the "Please replace volume" requester (dos)
                move.l  #ERROR_DEVICE_NOT_MOUNTED,d0
                rts
; .gt_arg(d0.b = offset in the packet of the lock argument | 0, d1 = mounted volume) -> Z = 1: accepted, else d0 = code
.gt_arg:
                move.l  d0,-(sp)
                and.w   #$FF,d0
                beq.s   .ga_ok
                move.l  0(a4,d0.w),d0                 ; BPTR lock | 0
                lsl.l   #2,d0
                bne.s   .ga_lock
                tst.l   d1                            ; root of the mounted disk
                bne.s   .ga_ok
                bsr     hnd_ctx
                beq.s   .ga_nodisk
                move.l  d0,a0
                cmp.l   #-1,HC_DTYPE(a0)
                beq.s   .ga_nodisk
                move.l  #ERROR_NOT_A_DOS_DISK,d0
                bra.s   .ga_err
.ga_nodisk:
                move.l  #ERROR_NO_DISK,d0
                bra.s   .ga_err
.ga_lock:
                move.l  d0,a0
                tst.l   d1
                beq.s   .ga_218
                cmp.l   FL_VOLUME(a0),d1
                beq.s   .ga_ok
.ga_218:
                move.l  FL_VOLUME(a0),HND_REFVOL
                move.l  #ERROR_DEVICE_NOT_MOUNTED,d0
.ga_err:
                addq.l  #4,sp
                tst.l   d0                            ; Z = 0
                rts
.ga_ok:
                move.l  (sp)+,d0
                cmp.w   d0,d0                         ; Z = 1
                rts
; action, offsets (high byte: 2nd lock, low byte: 1st lock); $80: file state in ARG1
hnd_gtab:
                dc.w    ACTION_LOCATE_OBJECT,DP_ARG1
                dc.w    ACTION_EXAMINE_OBJECT,DP_ARG1
                dc.w    ACTION_EXAMINE_NEXT,DP_ARG1
                dc.w    ACTION_PARENT,DP_ARG1
                dc.w    ACTION_COPY_DIR,DP_ARG1
                dc.w    ACTION_DELETE_OBJECT,DP_ARG1
                dc.w    ACTION_RENAME_OBJECT,DP_ARG3<<8|DP_ARG1
                dc.w    ACTION_CREATE_DIR,DP_ARG1
                dc.w    ACTION_SET_PROTECT,DP_ARG2
                dc.w    ACTION_SET_COMMENT,DP_ARG2
                dc.w    ACTION_INFO,DP_ARG1
                dc.w    ACTION_FINDINPUT,DP_ARG2
                dc.w    ACTION_FINDOUTPUT,DP_ARG2
                dc.w    ACTION_FINDUPDATE,DP_ARG2
                dc.w    ACTION_READ,$80
                dc.w    ACTION_WRITE,$80
                dc.w    ACTION_SEEK,$80
                dc.w    0

; hnd_usevol -> d0 = BPTR of the mounted volume (HC_VOLUME) | 0, its use count increased (lock or open file).
; hnd_unusevol(d0 = BPTR volume | 0): count decreased. Both preserve everything except d0.
hnd_usevol:
                move.l  a1,-(sp)
                bsr     hnd_ctx
                beq.s   .uv_ret
                move.l  d0,a1
                move.l  HC_VOLUME(a1),d0
                beq.s   .uv_ret
                lsl.l   #2,d0
                move.l  d0,a1
                addq.l  #1,DOL_USE(a1)
                lsr.l   #2,d0
.uv_ret:
                move.l  (sp)+,a1
                rts
hnd_unusevol:
                lsl.l   #2,d0
                beq.s   .un_ret
                move.l  a0,-(sp)
                move.l  d0,a0
                tst.l   DOL_USE(a0)
                beq.s   .un_z
                subq.l  #1,DOL_USE(a0)
.un_z:
                move.l  (sp)+,a0
.un_ret:
                rts

; hnd_lockkey(d0 = BPTR FileLock | 0) -> d0 = locked header block (fl_Key) | 0 (= root for ofs_*). Clobbers a0.
hnd_lockkey:
                lsl.l   #2,d0
                beq.s   .lk_root
                move.l  d0,a0
                move.l  FL_KEY(a0),d0
.lk_root:
                rts
; hnd_cstr(d0 = BPTR BSTR, a1 = destination HND_NAMEBUF): C string (bounded length). Clobbers d0/d1/a0/a1.
hnd_cstr:
                lsl.l   #2,d0
                move.l  d0,a0
                moveq   #0,d1
                move.b  (a0)+,d1
                cmp.w   #HND_NAMEBUF-1,d1
                bls.s   .cs_nx
                moveq   #HND_NAMEBUF-1,d1
                bra.s   .cs_nx
.cs_cp:
                move.b  (a0)+,(a1)+
.cs_nx:
                dbra    d1,.cs_cp
                clr.b   (a1)
                rts
hnd_slash:
                dc.b    "/",0
                even
